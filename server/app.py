"""Local Dramix backend prototype; Python 3.11+, standard library only."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

MAX_BODY = 64 * 1024
STATUSES = {"watching", "plans", "completed", "hold", "dropped"}
GATEWAY_PARAMS = {
    "list": {"types", "limit", "sort", "order", "year", "genres", "countries",
             "all_status", "with_material_data", "with_episodes", "minimal_age", "next"},
    "search": {"title", "id", "kinopoisk_id", "imdb_id", "shikimori_id", "mdl_id",
               "types", "limit", "year", "genres", "strict", "with_material_data",
               "with_episodes", "next"},
    "translations": set(),
}


class APIError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message
        super().__init__(message)


def require(condition, status=400, message="Invalid request"):
    if not condition:
        raise APIError(status, message)


def integer(value, minimum=0, maximum=2**53 - 1):
    require(type(value) is int and minimum <= value <= maximum)
    return value


def work_key(value):
    require(isinstance(value, str) and 1 <= len(value) <= 200
            and not any(ord(c) < 32 for c in value), message="Invalid work_key")
    return value


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def password_hash(password, salt):
    return hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1, dklen=32)


class Store:
    def __init__(self, path, clock=time.time, session_ttl=7 * 86400):
        self.clock, self.session_ttl = clock, session_ttl
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA busy_timeout=5000")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS users(
          id TEXT PRIMARY KEY, username TEXT UNIQUE NOT NULL,
          salt BLOB NOT NULL, password BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS sessions(
          token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
          expires REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS revisions(id INTEGER PRIMARY KEY AUTOINCREMENT);
        CREATE TABLE IF NOT EXISTS library(
          user_id TEXT NOT NULL REFERENCES users(id), work_key TEXT NOT NULL,
          revision INTEGER NOT NULL, deleted INTEGER NOT NULL, data TEXT NOT NULL,
          PRIMARY KEY(user_id, work_key));
        CREATE INDEX IF NOT EXISTS library_sync ON library(user_id, revision);
        CREATE TABLE IF NOT EXISTS checkpoints(
          user_id TEXT NOT NULL REFERENCES users(id), work_key TEXT NOT NULL,
          season INTEGER NOT NULL, episode INTEGER NOT NULL,
          revision INTEGER NOT NULL, deleted INTEGER NOT NULL, data TEXT NOT NULL,
          PRIMARY KEY(user_id, work_key, season, episode));
        CREATE INDEX IF NOT EXISTS checkpoints_sync ON checkpoints(user_id, revision);
        CREATE TABLE IF NOT EXISTS operations(
          user_id TEXT NOT NULL REFERENCES users(id), operation_id TEXT NOT NULL,
          fingerprint TEXT NOT NULL, response TEXT NOT NULL,
          PRIMARY KEY(user_id, operation_id));
        CREATE TABLE IF NOT EXISTS comments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL REFERENCES users(id), work_key TEXT NOT NULL,
          season INTEGER NOT NULL, episode INTEGER NOT NULL, text TEXT NOT NULL,
          spoiler INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
          created REAL NOT NULL, updated REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS episode_comments
          ON comments(work_key, season, episode, id);
        CREATE TABLE IF NOT EXISTS reports(
          comment_id INTEGER NOT NULL REFERENCES comments(id),
          user_id TEXT NOT NULL REFERENCES users(id), reason TEXT NOT NULL,
          created REAL NOT NULL, PRIMARY KEY(comment_id, user_id));
        """)
        # Version 2 adds durable episode checkpoints. Existing prototype
        # databases retain accounts/library and backfill their last pointer once.
        if self.db.execute("PRAGMA user_version").fetchone()[0] < 2:
            with self.transaction():
                rows = self.db.execute(
                    "SELECT user_id,work_key,data FROM library WHERE deleted=0").fetchall()
                for row in rows:
                    try:
                        progress = json.loads(row["data"]).get("progress")
                        if progress is not None:
                            self.checkpoint_fields(progress)
                            self.checkpoint_put(row["user_id"], row["work_key"], progress)
                    except (APIError, ValueError, TypeError, AttributeError):
                        continue
                self.db.execute("PRAGMA user_version=2")
        self.dummy_salt = b"dramix-dummy-salt"
        self.dummy_hash = password_hash("dummy-password", self.dummy_salt)

    @contextmanager
    def transaction(self):
        with self.lock:
            self.db.execute("BEGIN IMMEDIATE")
            try:
                yield
                self.db.execute("COMMIT")
            except BaseException:
                self.db.execute("ROLLBACK")
                raise

    def register(self, body):
        username, password = self.credentials(body)
        salt, uid = secrets.token_bytes(16), secrets.token_hex(16)
        hashed = password_hash(password, salt)
        try:
            with self.transaction():
                self.db.execute("INSERT INTO users VALUES(?,?,?,?)",
                                (uid, username, salt, hashed))
                return self.new_session(uid)
        except sqlite3.IntegrityError:
            raise APIError(409, "Username already exists") from None

    @staticmethod
    def credentials(body):
        require(isinstance(body, dict))
        username, password = body.get("username"), body.get("password")
        require(isinstance(username, str) and
                re.fullmatch(r"[A-Za-z0-9_.-]{3,40}", username) is not None,
                message="Username must contain 3–40 letters, digits, _, . or -")
        require(isinstance(password, str) and 12 <= len(password) <= 256,
                message="Password must contain 12–256 characters")
        return username.lower(), password

    def new_session(self, uid):
        token = secrets.token_urlsafe(32)
        expires = self.clock() + self.session_ttl
        self.db.execute("DELETE FROM sessions WHERE expires <= ?", (self.clock(),))
        self.db.execute("INSERT INTO sessions VALUES(?,?,?)",
                        (hashlib.sha256(token.encode()).hexdigest(), uid, expires))
        return {"token": token, "expires_at": expires, "user_id": uid}

    def login(self, body):
        username, password = self.credentials(body)
        with self.lock:
            row = self.db.execute("SELECT * FROM users WHERE username=?",
                                  (username,)).fetchone()
        actual = password_hash(password, row["salt"] if row else self.dummy_salt)
        require(hmac.compare_digest(actual, row["password"] if row else self.dummy_hash)
                and row is not None, 401, "Invalid credentials")
        with self.transaction():
            return self.new_session(row["id"])

    def authenticate(self, token):
        require(isinstance(token, str) and 1 <= len(token) <= 256, 401,
                "Authentication required")
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            row = self.db.execute("SELECT user_id, expires FROM sessions WHERE token_hash=?",
                                  (digest,)).fetchone()
        require(row is not None and row["expires"] > self.clock(), 401,
                "Session expired or invalid")
        return row["user_id"]

    def logout(self, token):
        with self.transaction():
            self.db.execute("DELETE FROM sessions WHERE token_hash=?",
                            (hashlib.sha256(token.encode()).hexdigest(),))
        return {"ok": True}

    def mutate(self, uid, operation_id, route, body, action):
        require(isinstance(operation_id, str) and
                re.fullmatch(r"[A-Za-z0-9_.:-]{8,128}", operation_id) is not None,
                message="An 8–128 character Idempotency-Key is required")
        fingerprint = hashlib.sha256(canonical([route, body]).encode()).hexdigest()
        with self.transaction():
            previous = self.db.execute(
                "SELECT fingerprint,response FROM operations WHERE user_id=? AND operation_id=?",
                (uid, operation_id)).fetchone()
            if previous:
                require(previous["fingerprint"] == fingerprint, 409,
                        "Idempotency key was used for another operation")
                return json.loads(previous["response"])
            response = action()
            self.db.execute("INSERT INTO operations VALUES(?,?,?,?)",
                            (uid, operation_id, fingerprint, canonical(response)))
            return response

    @staticmethod
    def checkpoint_fields(progress):
        require(isinstance(progress, dict) and
                set(progress) <= {"season", "episode", "position_ms", "variant_id"})
        integer(progress.get("season"), 1, 10000)
        integer(progress.get("episode"), 1, 100000)
        integer(progress.get("position_ms"), 0, 7 * 86400000)
        if "variant_id" in progress:
            require(isinstance(progress["variant_id"], str)
                    and len(progress["variant_id"]) <= 200)
        return progress

    def checkpoint_put(self, uid, key, progress):
        revision = self.db.execute("INSERT INTO revisions DEFAULT VALUES").lastrowid
        self.db.execute("INSERT OR REPLACE INTO checkpoints VALUES(?,?,?,?,?,?,?)",
                        (uid, key, progress["season"], progress["episode"],
                         revision, 0, canonical(progress)))

    def library_write(self, uid, body, operation_id, delete=False):
        require(isinstance(body, dict))
        key = work_key(body.get("work_key"))
        base_revision = integer(body.get("base_revision"))
        allowed = {"work_key", "base_revision"} if delete else {
            "work_key", "base_revision", "restore", "favorite", "status",
            "rating", "progress", "checkpoints"}
        require(set(body) <= allowed)
        restore = body.get("restore", False)
        require(type(restore) is bool)
        patch = {k: v for k, v in body.items()
                 if k not in {"work_key", "base_revision", "restore", "checkpoints"}}
        imports = body.get("checkpoints", [])
        require(isinstance(imports, list) and len(imports) <= 100)
        require(delete or bool(patch) or bool(imports))
        if "favorite" in patch:
            require(type(patch["favorite"]) is bool)
        if "status" in patch:
            require(patch["status"] is None or
                    isinstance(patch["status"], str) and patch["status"] in STATUSES)
        if "rating" in patch:
            require(patch["rating"] is None or
                    type(patch["rating"]) is int and 1 <= patch["rating"] <= 5)
        if patch.get("progress") is not None:
            self.checkpoint_fields(patch["progress"])
        seen = set()
        for progress in imports:
            self.checkpoint_fields(progress)
            identity = (progress["season"], progress["episode"])
            require(identity not in seen, message="Duplicate imported episode")
            seen.add(identity)

        def action():
            row = self.db.execute(
                "SELECT data,deleted,revision FROM library WHERE user_id=? AND work_key=?",
                (uid, key)).fetchone()
            actual_revision = row["revision"] if row else 0
            require(actual_revision == base_revision, 409,
                    f"Library revision conflict; current revision is {actual_revision}")
            require(delete or not row or not row["deleted"] or restore, 409,
                    "Item was deleted; explicit restore with its current revision is required")
            require(not restore or row is not None and bool(row["deleted"]), 409,
                    "Restore requires an existing tombstone")
            data = json.loads(row["data"]) if row and not row["deleted"] else {}
            data.update(patch)
            if delete:
                episodes = self.db.execute(
                    "SELECT season,episode FROM checkpoints"
                    " WHERE user_id=? AND work_key=? AND deleted=0", (uid, key)).fetchall()
                for episode in episodes:
                    revision = self.db.execute("INSERT INTO revisions DEFAULT VALUES").lastrowid
                    self.db.execute(
                        "UPDATE checkpoints SET revision=?,deleted=1,data='{}'"
                        " WHERE user_id=? AND work_key=? AND season=? AND episode=?",
                        (revision, uid, key, episode["season"], episode["episode"]))
                data = {}
            else:
                for progress in imports:
                    self.checkpoint_put(uid, key, progress)
                if patch.get("progress") is not None:
                    self.checkpoint_put(uid, key, patch["progress"])
            revision = self.db.execute("INSERT INTO revisions DEFAULT VALUES").lastrowid
            self.db.execute("INSERT OR REPLACE INTO library VALUES(?,?,?,?,?)",
                            (uid, key, revision, int(delete), canonical(data)))
            return {"work_key": key, "revision": revision, "deleted": delete, "data": data}
        return self.mutate(uid, operation_id, "library:delete" if delete else "library:patch",
                           body, action)

    def checkpoint_sync(self, uid, key=None, after=0, limit=100):
        if key is not None:
            work_key(key)
        integer(after)
        integer(limit, 1, 200)
        with self.lock:
            sql = "SELECT * FROM checkpoints WHERE user_id=? AND revision>?"
            params = [uid, after]
            if key is not None:
                sql += " AND work_key=?"
                params.append(key)
            rows = self.db.execute(sql + " ORDER BY revision LIMIT ?",
                                   params + [limit + 1]).fetchall()
        selected = rows[:limit]
        return {
            "items": [{"work_key": r["work_key"], "season": r["season"],
                       "episode": r["episode"], "revision": r["revision"],
                       "deleted": bool(r["deleted"]), "data": json.loads(r["data"])}
                      for r in selected],
            "cursor": selected[-1]["revision"] if selected else after,
            "has_more": len(rows) > limit,
        }

    def library_sync(self, uid, after=0, limit=100):
        integer(after)
        integer(limit, 1, 200)
        with self.lock:
            rows = self.db.execute(
                "SELECT * FROM library WHERE user_id=? AND revision>? ORDER BY revision LIMIT ?",
                (uid, after, limit + 1)).fetchall()
        selected = rows[:limit]
        return {
            "items": [{"work_key": r["work_key"], "revision": r["revision"],
                       "deleted": bool(r["deleted"]), "data": json.loads(r["data"])}
                      for r in selected],
            "cursor": selected[-1]["revision"] if selected else after,
            "has_more": len(rows) > limit,
        }

    @staticmethod
    def comment_fields(body):
        require(isinstance(body, dict))
        text, spoiler = body.get("text"), body.get("spoiler", False)
        require(isinstance(text, str) and 1 <= len(text.strip()) <= 3000)
        require(type(spoiler) is bool)
        return text.strip(), spoiler

    def comment_create(self, uid, body, operation_id):
        key = work_key(body.get("work_key"))
        season, episode = integer(body.get("season"), 1, 10000), integer(
            body.get("episode"), 1, 100000)
        text, spoiler = self.comment_fields(body)

        def action():
            now = self.clock()
            comment_id = self.db.execute(
                "INSERT INTO comments(user_id,work_key,season,episode,text,spoiler,created,updated)"
                " VALUES(?,?,?,?,?,?,?,?)",
                (uid, key, season, episode, text, int(spoiler), now, now)).lastrowid
            return {"id": comment_id, "ok": True}
        return self.mutate(uid, operation_id, "comments:create", body, action)

    def comments(self, key, season, episode, after=0, reveal=False, limit=50):
        work_key(key)
        integer(season, 1, 10000)
        integer(episode, 1, 100000)
        integer(after)
        integer(limit, 1, 100)
        with self.lock:
            rows = self.db.execute(
                "SELECT c.*,u.username FROM comments c JOIN users u ON u.id=c.user_id"
                " WHERE work_key=? AND season=? AND episode=? AND c.id>? ORDER BY c.id LIMIT ?",
                (key, season, episode, after, limit + 1)).fetchall()
        selected = rows[:limit]
        return {"items": [
            {"id": r["id"], "author": r["username"], "author_id": r["user_id"],
             "text": None if r["deleted"] or r["spoiler"] and not reveal else r["text"],
             "spoiler": bool(r["spoiler"]), "deleted": bool(r["deleted"]),
             "created_at": r["created"], "updated_at": r["updated"]} for r in selected],
             "cursor": selected[-1]["id"] if selected else after, "has_more": len(rows) > limit}

    def comment_change(self, uid, comment_id, body, operation_id, delete=False):
        integer(comment_id, 1)
        text, spoiler = ("", False) if delete else self.comment_fields(body)

        def action():
            row = self.db.execute("SELECT * FROM comments WHERE id=?", (comment_id,)).fetchone()
            require(row is not None, 404, "Comment not found")
            require(row["user_id"] == uid, 403, "Only the author may change this comment")
            require(delete or not row["deleted"], 409, "Comment was deleted")
            self.db.execute("UPDATE comments SET text=?,spoiler=?,deleted=?,updated=? WHERE id=?",
                            (text, int(spoiler), int(delete), self.clock(), comment_id))
            return {"id": comment_id, "deleted": delete}
        return self.mutate(uid, operation_id,
                           f"comments:{comment_id}:{'delete' if delete else 'patch'}",
                           body, action)

    def report(self, uid, comment_id, body, operation_id):
        integer(comment_id, 1)
        reason = body.get("reason")
        require(isinstance(reason, str) and 1 <= len(reason.strip()) <= 500)

        def action():
            row = self.db.execute("SELECT deleted FROM comments WHERE id=?",
                                  (comment_id,)).fetchone()
            require(row is not None and not row["deleted"], 404, "Comment not found")
            self.db.execute("INSERT OR IGNORE INTO reports VALUES(?,?,?,?)",
                            (comment_id, uid, reason.strip(), self.clock()))
            return {"ok": True}
        return self.mutate(uid, operation_id, f"comments:{comment_id}:report", body, action)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Gateway:
    def __init__(self, token, ttl=60, timeout=8, clock=time.time, fetch=None):
        self.token, self.ttl, self.timeout, self.clock = token, ttl, timeout, clock
        self.cache = {}
        self.lock = threading.Lock()
        self.fetch = fetch or self._fetch

    def query(self, endpoint, params):
        require(endpoint in GATEWAY_PARAMS, 404, "Unknown catalog endpoint")
        require(set(params) <= GATEWAY_PARAMS[endpoint], message="Unsupported catalog parameter")
        require(all(isinstance(v, str) and len(v) <= 500 for v in params.values()))
        if "limit" in params:
            require(params["limit"].isdigit())
            integer(int(params["limit"]), 1, 50)
        require(bool(self.token), 503, "Server catalog access is not configured")
        key = canonical([endpoint, params])
        with self.lock:
            item = self.cache.get(key)
            if item and item[0] > self.clock():
                return item[1]
        url = "https://kodik-api.com/" + endpoint + "?" + urlencode(
            {**params, "token": self.token})
        try:
            result = self.fetch(url)
        except (OSError, ValueError, HTTPError, URLError):
            raise APIError(502, "Catalog provider is unavailable") from None
        valid = isinstance(result, list) if endpoint == "translations" else (
            isinstance(result, dict) and isinstance(result.get("results"), list)
            and isinstance(result.get("total"), (int, float)) and "error" not in result)
        require(valid, 502, "Catalog provider returned an invalid response")
        # Never return a provider cursor carrying server credentials. The client
        # must call our endpoint with next; URLs are not accepted as proxy targets.
        if isinstance(result, dict):
            result = dict(result)
            raw_cursor = result.pop("next_page", None)
            result["next_cursor"] = None
            if isinstance(raw_cursor, str):
                try:
                    uri = urlsplit(raw_cursor)
                    if (uri.scheme == "https" and uri.hostname == "kodik-api.com"
                            and uri.port in (None, 443) and not uri.username
                            and not uri.fragment and uri.path in ("/list", "/search")):
                        query = parse_qs(uri.query)
                        result["next_cursor"] = query.get("next", [None])[0]
                except ValueError:
                    pass
        with self.lock:
            if len(self.cache) >= 256:
                self.cache.clear()
            self.cache[key] = (self.clock() + self.ttl, result)
        return result

    def _fetch(self, url):
        request = Request(url, headers={"Accept": "application/json",
                          "User-Agent": "Mozilla/5.0 DramixPrototype/0.1"})
        with build_opener(NoRedirect()).open(request, timeout=self.timeout) as response:
            raw = response.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024:
                raise ValueError("Provider response too large")
            return json.loads(raw)


class Application:
    def __init__(self, store, gateway):
        self.store, self.gateway = store, gateway
        self.rate_lock, self.auth_attempts = threading.Lock(), {}

    def auth_rate(self, ip):
        with self.rate_lock:
            now = time.monotonic()
            attempts = [x for x in self.auth_attempts.get(ip, []) if x > now - 60]
            require(len(attempts) < 10, 429, "Too many authentication attempts")
            self.auth_attempts[ip] = attempts + [now]
            if len(self.auth_attempts) > 1000:
                self.auth_attempts = {k: v for k, v in self.auth_attempts.items()
                                      if v and v[-1] > now - 60}

    def dispatch(self, method, path, query, body, token, operation_id, ip):
        if method == "GET" and path == "/health":
            return {"ok": True, "prototype": True}
        if method == "POST" and path in ("/v1/auth/register", "/v1/auth/login"):
            self.auth_rate(ip)
            return self.store.register(body) if path.endswith("register") else self.store.login(body)
        if method == "GET" and path.startswith("/v1/catalog/"):
            return self.gateway.query(path.removeprefix("/v1/catalog/"), query)
        if method == "GET" and path == "/v1/comments":
            try:
                return self.store.comments(query.get("work_key"), int(query.get("season", "0")),
                    int(query.get("episode", "0")), int(query.get("after", "0")),
                    query.get("reveal_spoilers") == "true", int(query.get("limit", "50")))
            except ValueError:
                raise APIError(400, "Invalid query") from None
        uid = self.store.authenticate(token)
        if method == "POST" and path == "/v1/auth/logout":
            return self.store.logout(token)
        if method == "GET" and path == "/v1/checkpoints":
            try:
                return self.store.checkpoint_sync(
                    uid, query.get("work_key"), int(query.get("after", "0")),
                    int(query.get("limit", "100")))
            except ValueError:
                raise APIError(400, "Invalid query") from None
        if path == "/v1/library":
            if method == "GET":
                try:
                    return self.store.library_sync(uid, int(query.get("after", "0")),
                                                   int(query.get("limit", "100")))
                except ValueError:
                    raise APIError(400, "Invalid query") from None
            if method in ("PATCH", "DELETE"):
                return self.store.library_write(uid, body, operation_id, method == "DELETE")
        if method == "POST" and path == "/v1/comments":
            return self.store.comment_create(uid, body, operation_id)
        match = re.fullmatch(r"/v1/comments/([1-9][0-9]*)(/report)?", path)
        if match:
            cid = int(match.group(1))
            if method == "POST" and match.group(2):
                return self.store.report(uid, cid, body, operation_id)
            if not match.group(2) and method in ("PATCH", "DELETE"):
                return self.store.comment_change(uid, cid, body, operation_id, method == "DELETE")
        raise APIError(404, "Route not found")


def handler_for(application):
    class Handler(BaseHTTPRequestHandler):
        server_version = "DramixPrototype/0.1"

        def log_message(self, format, *args):
            # Avoid persisting request URLs, passwords or bearer tokens.
            return

        def do_GET(self):
            self.handle_api()

        def do_POST(self):
            self.handle_api()

        def do_PATCH(self):
            self.handle_api()

        def do_DELETE(self):
            self.handle_api()

        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def handle_api(self):
            try:
                require(not self.headers.get("Transfer-Encoding"), 400)
                length = int(self.headers.get("Content-Length", "0"))
                require(0 <= length <= MAX_BODY, 413, "Request body too large")
                body = json.loads(self.rfile.read(length)) if length else {}
                require(isinstance(body, dict))
                url = urlsplit(self.path)
                values = parse_qs(url.query, keep_blank_values=True)
                require(all(len(v) == 1 for v in values.values()),
                        message="Duplicate query parameter")
                query = {k: v[0] for k, v in values.items()}
                auth = self.headers.get("Authorization", "")
                token = auth[7:] if auth.startswith("Bearer ") else ""
                result = application.dispatch(
                    self.command, url.path, query, body, token,
                    self.headers.get("Idempotency-Key"), self.client_address[0])
                self.respond(200, result)
            except APIError as error:
                self.respond(error.status, {"error": error.message})
            except (ValueError, TypeError):
                self.respond(400, {"error": "Invalid request"})
            except Exception:
                self.respond(500, {"error": "Internal server error"})

        def respond(self, status, body):
            data = canonical(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(data)
    return Handler


def main():
    host = os.environ.get("DRAMIX_HOST", "127.0.0.1")
    port = int(os.environ.get("DRAMIX_PORT", "8080"))
    path = os.environ.get("DRAMIX_DB", "dramix.sqlite3")
    store = Store(path)
    gateway = Gateway(os.environ.get("KODIK_TOKEN", ""))
    server = ThreadingHTTPServer((host, port), handler_for(Application(store, gateway)))
    server.daemon_threads = True
    print(f"Dramix local prototype listening on {host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        store.db.close()


if __name__ == "__main__":
    main()
