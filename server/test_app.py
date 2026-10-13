"""Deterministic local tests; no Kodik, real credentials or remote network."""
import json
import threading
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
        self.store.library_write(self.a, {"work_key": "kinopoisk:123", "favorite": True}, "op-first-01")
        self.assertEqual(self.store.library_sync(self.b)["items"], [])
        item = self.store.library_sync(self.a)["items"][0]
        self.assertEqual(item["data"]["favorite"], True)

    def test_retry_is_idempotent_and_cannot_replay_over_newer_data(self):
        first = {"work_key": "kinopoisk:123", "favorite": True}
        result = self.store.library_write(self.a, first, "op-first-01")
        self.store.library_write(self.a, {"work_key": "kinopoisk:123", "favorite": False}, "op-second-02")
        retry = self.store.library_write(self.a, first, "op-first-01")
        self.assertEqual(retry, result)
        self.assertFalse(self.store.library_sync(self.a)["items"][0]["data"]["favorite"])
        with self.assertRaises(APIError) as error:
            self.store.library_write(self.a, {"work_key": "kinopoisk:123", "rating": 4}, "op-first-01")
        self.assertEqual(error.exception.status, 409)

    def test_partial_updates_keep_other_fields_and_delete_syncs_tombstone(self):
        self.store.library_write(self.a, {
            "work_key": "imdb:tt123", "favorite": True, "status": "watching",
            "progress": {"season": 2, "episode": 3, "position_ms": 12000, "variant_id": "serial-7"}
        }, "op-first-01")
        self.store.library_write(self.a, {"work_key": "imdb:tt123", "rating": 5}, "op-second-02")
        page = self.store.library_sync(self.a)
        self.assertTrue(page["items"][0]["data"]["favorite"])
        self.assertEqual(page["items"][0]["data"]["progress"]["season"], 2)
        deleted = self.store.library_write(self.a, {"work_key": "imdb:tt123"}, "op-delete-03", True)
        delta = self.store.library_sync(self.a, page["cursor"])
        self.assertEqual(delta["items"], [deleted])
        self.assertEqual(deleted["data"], {})
        self.assertTrue(deleted["deleted"])

    def test_pagination_advances_without_exposing_another_users_rows(self):
        for i in range(3):
            self.store.library_write(self.a, {"work_key": f"kodik:{i}", "rating": 3}, f"op-title-{i}")
        first = self.store.library_sync(self.a, limit=2)
        self.assertTrue(first["has_more"])
        second = self.store.library_sync(self.a, first["cursor"], limit=2)
        self.assertEqual(len(second["items"]), 1)
        self.assertFalse(second["has_more"])
        self.assertEqual(len({i["work_key"] for i in first["items"] + second["items"]}), 3)

    def test_invalid_progress_rolls_back_without_an_operation(self):
        with self.assertRaises(APIError):
            self.store.library_write(self.a, {
                "work_key": "kodik:bad", "progress": {"season": 1, "episode": 0, "position_ms": 0}
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
                         {"work_key": "kinopoisk:123", "favorite": True}, headers)[0], 200)
        status, page = self.request("/v1/library", headers=headers)
        self.assertEqual(page["items"][0]["work_key"], "kinopoisk:123")
        self.assertEqual(self.request("/v1/catalog/list?token=bad")[0], 400)
        self.assertEqual(self.request("/v1/catalog/list")[0], 503)
        self.assertEqual(self.request("/v1/comments?season=nope")[0], 400)
        self.assertEqual(self.request("/v1/auth/register", "POST",
                                     {"password": "x" * 70000})[0], 413)


if __name__ == "__main__":
    unittest.main()
