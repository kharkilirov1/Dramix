"""Deterministic local tests; no Kodik, real credentials or remote network."""
import json
import threading
import tempfile
import os
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer

from app import APIError, Application, Gateway, Store, handler_for


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.now = 1000.0
        self.store = Store(":memory:", clock=lambda: self.now, session_ttl=60)
        self.first = self.store.register({"username": "alice", "password": "secure-test-password"})
        self.second = self.store.register({"username": "bob", "password": "other-test-password"})
        self.a, self.b = self.first["user_id"], self.second["user_id"]

    def tearDown(self):
        self.store.db.close()

    def test_passwords_and_sessions_are_not_stored_in_cleartext(self):
        row = self.store.db.execute("SELECT * FROM users WHERE id=?", (self.a,)).fetchone()
        self.assertNotEqual(row["password"], b"secure-test-password")
        tokens = [r[0] for r in self.store.db.execute("SELECT token_hash FROM sessions")]
        self.assertNotIn(self.first["token"], tokens)
        self.assertEqual(self.store.authenticate(self.first["token"]), self.a)
        self.now += 61
        with self.assertRaises(APIError) as error:
            self.store.authenticate(self.first["token"])
        self.assertEqual(error.exception.status, 401)

    def test_login_failure_and_logout(self):
        with self.assertRaises(APIError) as error:
            self.store.login({"username": "alice", "password": "incorrect-password"})
        self.assertEqual(error.exception.status, 401)
        session = self.store.login({"username": "ALICE", "password": "secure-test-password"})
        self.assertEqual(self.store.authenticate(session["token"]), self.a)
        self.store.logout(session["token"])
        with self.assertRaises(APIError):
            self.store.authenticate(session["token"])

    def test_library_is_user_scoped(self):
        self.store.library_write(self.a, {"work_key": "kinopoisk:123", "base_revision": 0, "favorite": True}, "op-first-01")
        self.assertEqual(self.store.library_sync(self.b)["items"], [])
        item = self.store.library_sync(self.a)["items"][0]
        self.assertEqual(item["data"]["favorite"], True)

    def test_retry_is_idempotent_and_cannot_replay_over_newer_data(self):
        first = {"work_key": "kinopoisk:123", "base_revision": 0, "favorite": True}
        result = self.store.library_write(self.a, first, "op-first-01")
        self.store.library_write(self.a, {"work_key": "kinopoisk:123", "base_revision": result["revision"], "favorite": False}, "op-second-02")
        retry = self.store.library_write(self.a, first, "op-first-01")
        self.assertEqual(retry, result)
        self.assertFalse(self.store.library_sync(self.a)["items"][0]["data"]["favorite"])
        with self.assertRaises(APIError) as error:
            self.store.library_write(self.a, {"work_key": "kinopoisk:123", "base_revision": result["revision"], "rating": 4}, "op-first-01")
        self.assertEqual(error.exception.status, 409)

    def test_partial_updates_keep_other_fields_and_delete_syncs_tombstone(self):
        self.store.library_write(self.a, {
            "work_key": "imdb:tt123", "base_revision": 0, "favorite": True, "status": "watching",
            "progress": {"season": 2, "episode": 3, "position_ms": 12000, "variant_id": "serial-7"}
        }, "op-first-01")
        self.store.library_write(self.a, {"work_key": "imdb:tt123",
            "base_revision": self.store.library_sync(self.a)["items"][0]["revision"],
            "rating": 5}, "op-second-02")
        page = self.store.library_sync(self.a)
        self.assertTrue(page["items"][0]["data"]["favorite"])
        self.assertEqual(page["items"][0]["data"]["progress"]["season"], 2)
        deleted = self.store.library_write(self.a, {"work_key": "imdb:tt123", "base_revision": page["items"][0]["revision"]}, "op-delete-03", True)
        delta = self.store.library_sync(self.a, page["cursor"])
        self.assertEqual(delta["items"], [deleted])
        self.assertEqual(deleted["data"], {})
        self.assertTrue(deleted["deleted"])

    def test_pagination_advances_without_exposing_another_users_rows(self):
        for i in range(3):
            self.store.library_write(self.a, {"work_key": f"kodik:{i}", "base_revision": 0, "rating": 3}, f"op-title-{i}")
        first = self.store.library_sync(self.a, limit=2)
        self.assertTrue(first["has_more"])
        second = self.store.library_sync(self.a, first["cursor"], limit=2)
        self.assertEqual(len(second["items"]), 1)
        self.assertFalse(second["has_more"])
        self.assertEqual(len({i["work_key"] for i in first["items"] + second["items"]}), 3)

    def test_invalid_progress_rolls_back_without_an_operation(self):
        with self.assertRaises(APIError):
            self.store.library_write(self.a, {
                "work_key": "kodik:bad", "base_revision": 0, "progress": {"season": 1, "episode": 0, "position_ms": 0}
            }, "op-invalid-01")
        self.assertEqual(self.store.library_sync(self.a)["items"], [])
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM operations").fetchone()[0], 0)

    def test_comments_are_episode_scoped_hide_spoilers_and_retry_once(self):
        body = {"work_key": "kinopoisk:123", "season": 2, "episode": 3,
                "text": "A spoiler", "spoiler": True}
        created = self.store.comment_create(self.a, body, "comment-first-01")
        self.assertEqual(created, self.store.comment_create(self.a, body, "comment-first-01"))
        self.assertEqual(self.store.comments("kinopoisk:123", 2, 4)["items"], [])
        hidden = self.store.comments("kinopoisk:123", 2, 3)["items"]
        self.assertEqual(len(hidden), 1)
        self.assertIsNone(hidden[0]["text"])
        revealed = self.store.comments("kinopoisk:123", 2, 3, reveal=True)
        self.assertEqual(revealed["items"][0]["text"], "A spoiler")

    def test_comment_edit_delete_ownership_and_reports(self):
        created = self.store.comment_create(self.a, {
            "work_key": "kodik:7", "season": 1, "episode": 1, "text": "Hello"
        }, "comment-first-01")
        cid = created["id"]
        with self.assertRaises(APIError) as error:
            self.store.comment_change(self.b, cid, {"text": "Hijack"}, "comment-hijack-01")
        self.assertEqual(error.exception.status, 403)
        self.store.report(self.b, cid, {"reason": "Spam"}, "report-first-01")
        self.store.report(self.b, cid, {"reason": "Spam"}, "report-second-02")
        self.assertEqual(self.store.db.execute("SELECT COUNT(*) FROM reports").fetchone()[0], 1)
        self.store.comment_change(self.a, cid, {"text": "Edited"}, "comment-edit-01")
        self.assertEqual(self.store.comments("kodik:7", 1, 1)["items"][0]["text"], "Edited")
        self.store.comment_change(self.a, cid, {}, "comment-delete-01", True)
        deleted = self.store.comments("kodik:7", 1, 1, reveal=True)["items"][0]
        self.assertTrue(deleted["deleted"])
        self.assertIsNone(deleted["text"])


    def test_episode_history_is_separate_from_last_resume(self):
        first = self.store.library_write(self.a, {
            "work_key": "kinopoisk:7", "base_revision": 0,
            "progress": {"season": 1, "episode": 1, "position_ms": 60000}
        }, "checkpoint-first-01")
        second = self.store.library_write(self.a, {
            "work_key": "kinopoisk:7", "base_revision": first["revision"],
            "progress": {"season": 1, "episode": 2, "position_ms": 90000}
        }, "checkpoint-second-02")
        self.store.library_write(self.a, {
            "work_key": "kinopoisk:7", "base_revision": second["revision"],
            "progress": {"season": 1, "episode": 1, "position_ms": 120000}
        }, "checkpoint-third-03")
        episodes = self.store.checkpoint_sync(self.a)["items"]
        self.assertEqual({(p["season"], p["episode"]): p["data"]["position_ms"]
                          for p in episodes}, {(1, 1): 120000, (1, 2): 90000})
        resume = self.store.library_sync(self.a)["items"][0]["data"]["progress"]
        self.assertEqual(resume["episode"], 1)
        self.assertEqual(self.store.checkpoint_sync(self.b)["items"], [])

    def test_stale_patch_and_stale_delete_cannot_replace_current_data(self):
        first = self.store.library_write(self.a, {
            "work_key": "kodik:7", "base_revision": 0, "favorite": True
        }, "revision-first-01")
        second = self.store.library_write(self.a, {
            "work_key": "kodik:7", "base_revision": first["revision"], "rating": 4
        }, "revision-second-02")
        for delete in (False, True):
            body = {"work_key": "kodik:7", "base_revision": first["revision"]}
            if not delete:
                body["favorite"] = False
            with self.assertRaises(APIError) as error:
                self.store.library_write(self.a, body, f"revision-stale-{delete}", delete)
            self.assertEqual(error.exception.status, 409)
        self.assertEqual(self.store.library_sync(self.a)["items"][0], second)

    def test_delete_tombstones_episodes_and_requires_explicit_current_restore(self):
        first_body = {"work_key": "kodik:7", "base_revision": 0,
                      "progress": {"season": 2, "episode": 3, "position_ms": 4000}}
        first = self.store.library_write(self.a, first_body, "delete-first-01")
        checkpoint_cursor = self.store.checkpoint_sync(self.a)["cursor"]
        deleted = self.store.library_write(self.a, {
            "work_key": "kodik:7", "base_revision": first["revision"]
        }, "delete-second-02", True)
        episodes = self.store.checkpoint_sync(self.a, after=checkpoint_cursor)["items"]
        self.assertTrue(episodes[0]["deleted"])
        self.assertEqual(episodes[0]["data"], {})
        # Replaying a previously successful operation is inert even after delete.
        self.assertEqual(self.store.library_write(self.a, first_body, "delete-first-01"), first)
        for revision in (0, first["revision"], deleted["revision"]):
            with self.assertRaises(APIError) as error:
                self.store.library_write(self.a, {
                    "work_key": "kodik:7", "base_revision": revision, "favorite": True
                }, f"stale-resurrection-{revision}")
            self.assertEqual(error.exception.status, 409)
        restored = self.store.library_write(self.a, {
            "work_key": "kodik:7", "base_revision": deleted["revision"],
            "restore": True, "favorite": True
        }, "explicit-restore-01")
        self.assertFalse(restored["deleted"])
        self.assertTrue(self.store.checkpoint_sync(self.a)["items"][0]["deleted"])

    def test_atomic_checkpoint_import_preserves_all_episodes_and_explicit_resume(self):
        points = [{"season": 1, "episode": i, "position_ms": i * 1000}
                  for i in range(1, 4)]
        imported = self.store.library_write(self.a, {
            "work_key": "imdb:tt7", "base_revision": 0,
            "checkpoints": points, "progress": points[1]
        }, "import-checkpoints-01")
        first_page = self.store.checkpoint_sync(self.a, "imdb:tt7", limit=2)
        second_page = self.store.checkpoint_sync(
            self.a, "imdb:tt7", first_page["cursor"], limit=2)
        self.assertTrue(first_page["has_more"])
        self.assertEqual(len(first_page["items"] + second_page["items"]), 3)
        self.assertEqual(imported["data"]["progress"]["episode"], 2)
        self.assertEqual(self.store.library_write(self.a, {
            "work_key": "imdb:tt7", "base_revision": 0,
            "checkpoints": points, "progress": points[1]
        }, "import-checkpoints-01"), imported)

    def test_missing_revision_or_duplicate_import_rejected_without_changes(self):
        with self.assertRaises(APIError):
            self.store.library_write(self.a, {
                "work_key": "kodik:7", "favorite": True
            }, "missing-revision-01")
        point = {"season": 1, "episode": 1, "position_ms": 1000}
        with self.assertRaises(APIError):
            self.store.library_write(self.a, {
                "work_key": "kodik:7", "base_revision": 0, "checkpoints": [point, point]
            }, "duplicate-import-01")
        self.assertEqual(self.store.library_sync(self.a)["items"], [])
        self.assertEqual(self.store.checkpoint_sync(self.a)["items"], [])

    def test_checkpoints_survive_restart_and_legacy_pointer_migrates_once(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "test.sqlite3")
            original = Store(path)
            account = original.register({"username": "persist", "password": "persistent-password"})
            uid = account["user_id"]
            original.library_write(uid, {
                "work_key": "kodik:7", "base_revision": 0,
                "progress": {"season": 1, "episode": 1, "position_ms": 5000}
            }, "persist-first-01")
            # Simulate the previous prototype: library pointer but no episode table rows.
            original.db.execute("DELETE FROM checkpoints")
            original.db.execute("PRAGMA user_version=1")
            original.db.close()
            migrated = Store(path)
            self.assertEqual(migrated.authenticate(account["token"]), uid)
            points = migrated.checkpoint_sync(uid)["items"]
            self.assertEqual(points[0]["data"]["position_ms"], 5000)
            revision = points[0]["revision"]
            migrated.db.close()
            reopened = Store(path)
            self.assertEqual(reopened.checkpoint_sync(uid)["items"][0]["revision"], revision)
            reopened.db.close()


class GatewayTests(unittest.TestCase):
    def test_allowlist_rejects_tokens_urls_and_unknown_routes_before_fetch(self):
        calls = []
        gateway = Gateway("synthetic-test-secret", fetch=lambda url: calls.append(url))
        for endpoint, params in [("fetch", {}), ("list", {"token": "injected"}),
                                 ("search", {"url": "http://localhost"}),
                                 ("list", {"limit": "999"})]:
            with self.assertRaises(APIError):
                gateway.query(endpoint, params)
        self.assertEqual(calls, [])

    def test_cache_cursor_redaction_and_expiry(self):
        calls, now = [], [100]
        def fetch(url):
            calls.append(url)
            return {"total": 1, "results": [{"id": "serial-1"}],
                    "next_page": "https://kodik-api.com/list?token=synthetic-test-secret&next=page2"}
        gateway = Gateway("synthetic-test-secret", ttl=60, clock=lambda: now[0], fetch=fetch)
        result = gateway.query("list", {"limit": "10"})
        self.assertNotIn("next_page", result)
        self.assertEqual(result["next_cursor"], "page2")
        self.assertNotIn("synthetic-test-secret", json.dumps(result))
        gateway.query("list", {"limit": "10"})
        self.assertEqual(len(calls), 1)
        now[0] += 61
        gateway.query("list", {"limit": "10"})
        self.assertEqual(len(calls), 2)

    def test_bad_provider_response_is_not_cached(self):
        calls = []
        def fetch(url):
            calls.append(url)
            return {"error": "unavailable"}
        gateway = Gateway("synthetic-test-secret", fetch=fetch)
        for _ in range(2):
            with self.assertRaises(APIError) as error:
                gateway.query("list", {})
            self.assertEqual(error.exception.status, 502)
        self.assertEqual(len(calls), 2)

    def test_unconfigured_gateway_fails_without_fetch(self):
        gateway = Gateway("", fetch=lambda url: self.fail("should not fetch"))
        with self.assertRaises(APIError) as error:
            gateway.query("list", {})
        self.assertEqual(error.exception.status, 503)


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.store = Store(":memory:")
        self.app = Application(self.store, Gateway(""))
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(self.app))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.store.db.close()

    def request(self, path, method="GET", body=None, headers=None):
        data = None if body is None else json.dumps(body).encode()
        req = Request(self.base + path, data=data, method=method, headers=headers or {})
        try:
            with urlopen(req, timeout=2) as response:
                return response.status, json.load(response)
        except HTTPError as error:
            return error.code, json.load(error)

    def test_auth_library_and_body_restrictions_through_http(self):
        status, session = self.request("/v1/auth/register", "POST",
                                      {"username": "tester", "password": "secure-test-password"})
        self.assertEqual(status, 200)
        self.assertEqual(self.request("/v1/library")[0], 401)
        headers = {"Authorization": "Bearer " + session["token"],
                   "Idempotency-Key": "http-operation-01"}
        self.assertEqual(self.request("/v1/library", "PATCH",
                         {"work_key": "kinopoisk:123", "base_revision": 0, "favorite": True}, headers)[0], 200)
        status, page = self.request("/v1/library", headers=headers)
        self.assertEqual(page["items"][0]["work_key"], "kinopoisk:123")
        self.assertEqual(self.request("/v1/catalog/list?token=bad")[0], 400)
        self.assertEqual(self.request("/v1/catalog/list")[0], 503)
        self.assertEqual(self.request("/v1/comments?season=nope")[0], 400)
        self.assertEqual(self.request("/v1/auth/register", "POST",
                                     {"password": "x" * 70000})[0], 413)


    def test_configured_web_origin_receives_cors_and_unknown_origin_is_rejected(self):
        origin = "http://localhost:8321"
        self.app.allowed_origins.add(origin)
        with urlopen(Request(self.base + "/health", headers={"Origin": origin}), timeout=2) as response:
            self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)
            self.assertEqual(response.headers["Vary"], "Origin")
        req = Request(self.base + "/health", headers={"Origin": "https://evil.example"})
        with self.assertRaises(HTTPError) as error:
            urlopen(req, timeout=2)
        self.assertEqual(error.exception.code, 403)
        self.assertIsNone(error.exception.headers.get("Access-Control-Allow-Origin"))
        error.exception.close()

    def test_preflight_allows_auth_idempotency_and_rejects_unknown_headers(self):
        origin = "http://localhost:8321"
        self.app.allowed_origins.add(origin)
        headers = {"Origin": origin, "Access-Control-Request-Method": "PATCH",
                   "Access-Control-Request-Headers": "authorization, content-type, idempotency-key"}
        req = Request(self.base + "/v1/library", method="OPTIONS", headers=headers)
        with urlopen(req, timeout=2) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["Access-Control-Allow-Origin"], origin)
            self.assertIn("PATCH", response.headers["Access-Control-Allow-Methods"])
            self.assertIn("Idempotency-Key", response.headers["Access-Control-Allow-Headers"])
        headers["Access-Control-Request-Headers"] = "x-unapproved"
        self.assertEqual(self.request("/v1/library", "OPTIONS", headers=headers)[0], 403)
        headers["Origin"] = "https://evil.example"
        self.assertEqual(self.request("/v1/library", "OPTIONS", headers=headers)[0], 403)

    def test_cors_configuration_rejects_wildcard_remote_http_and_path(self):
        for origin in ("*", "http://remote.example", "https://example.com/path",
                       "https://user@example.com", "https://example.com:bad"):
            with self.assertRaises((APIError, ValueError)):
                Application(self.store, Gateway(""), allowed_origins=[origin])
        allowed = Application(self.store, Gateway(""),
                              allowed_origins=["https://app.example", "http://127.0.0.1:8321"])
        self.assertEqual(len(allowed.allowed_origins), 2)


if __name__ == "__main__":
    unittest.main()
