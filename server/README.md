# Dramix local backend prototype

Python 3.11+ and SQLite, using only the standard library. This draft adds a
separate service; **Flutter does not call it yet**. No external infrastructure,
billing, deployment, live Kodik verification or production-readiness claim.

## Run locally

From the repository:

```sh
cd server
python -m unittest -v
python app.py
```

The default address is http://127.0.0.1:8080. GET /health works without a token.
Set KODIK_TOKEN in your process environment to enable the catalog gateway.
The service does not download or rotate community credentials. Without that
variable, catalog requests return 503; accounts and personal library still work.
.env.example documents configuration; the service does not automatically load it.
Do not commit a real .env or database.

## API

JSON responses and request bodies. Use Authorization: Bearer <session-token>
for authenticated endpoints. Registration/login returns an opaque session token
with expiry; password hashing uses scrypt with individual random salts and only
SHA-256 token digests are stored. Logout revokes the current session. Session
lifetime defaults to seven days.

| Endpoint | Behavior |
|---|---|
| POST /v1/auth/register | username (3–40 ASCII letters/digits/_.-), password (12–256 characters) |
| POST /v1/auth/login | same fields; username is case insensitive |
| POST /v1/auth/logout | revoke session |
| GET /v1/catalog/list | allowlisted Kodik catalog parameters |
| GET /v1/catalog/search | title, external ID and other allowlisted search parameters |
| GET /v1/catalog/translations | available translations |
| GET /v1/library?after=0&limit=100 | authenticated changes, cursor, has_more |
| PATCH /v1/library | partial library update |
| DELETE /v1/library | work_key; syncable deletion tombstone |
| GET /v1/comments | work_key, season, episode, optional after/limit/reveal_spoilers=true |
| POST /v1/comments | authenticated work_key/season/episode/text/spoiler |
| PATCH /v1/comments/{id} | author-only replacement text/spoiler |
| DELETE /v1/comments/{id} | author-only deletion with text redacted |
| POST /v1/comments/{id}/report | authenticated reason; deduplicated per reporter |

Library and comment/report writes require an **Idempotency-Key** header (8–128
ASCII letters/digits/_.:-). Retries with the same key and identical operation
return the original response without repeating the write. Reusing a key for
different data returns 409. Keys are scoped to the authenticated user.
Authentication operations do not use this mechanism.

Example PATCH /v1/library body:

```json
{
  "work_key": "kinopoisk:123",
  "favorite": true,
  "status": "watching",
  "rating": 4,
  "progress": {
    "season": 2,
    "episode": 3,
    "position_ms": 120000,
    "variant_id": "serial-123"
  }
}
```

Fields may be updated individually. status/rating/progress accept null to clear.
status: watching/plans/completed/hold/dropped; rating: 1–5. Progress is a
checkpoint, not proof of completion or accumulated watch duration.

work_key is an **opaque stable content ID** supplied by the client. Suggested
namespaces matching the Flutter identity work: kinopoisk:<positive digits>,
imdb:tt<digits>, mdl:<positive digits>, shikimori:<positive digits>, fallback
kodik:<provider-record-id>. This service never merges names/years, discovers
aliases or replaces a provider playback ID. variant_id remains separate.

Sync returns current snapshots changed since after, including tombstones.
Keep polling while has_more is true; persist the returned cursor only after
applying that page. Do not advance your cursor using a mutation response:
other offline updates may exist before its revision. An idempotent replay can
return an older mutation response; it does not restore that snapshot on the
server. Conflicting new edits use last server-committed write per field;
compare-and-swap/vector-clock conflict resolution is not implemented.
DELETE removes all fields; a later PATCH explicitly recreates that item.

Comments belong to a **specific season and episode**. Spoiler bodies are null
unless reveal_spoilers=true; deleted bodies remain null in every response.
Reports are stored for later moderation; there is no moderator queue/UI yet.

## Gateway boundaries

Only /list, /search, /translations on fixed https://kodik-api.com are queried.
No client-supplied token, host, URL or arbitrary proxy target is accepted.
Redirects are refused; upstream timeout is eight seconds and responses are
bounded to 2 MiB. Valid successful JSON is cached in process for 60 seconds,
up to 256 parameter combinations; failures are not cached.

Provider next_page URLs are removed, so server credentials in them are not
returned. next_cursor contains the provider's next parameter when its origin
passes validation. Repeat the same catalog endpoint and filters with next=<cursor>;
this is a prototype contract and must be checked against recorded/live provider
responses before integrating Flutter. It does not yet adapt JSON to AnixartiOS.
It also does not resolve direct video streams, proxy media, or bypass iframe
restrictions: playback still needs a separate client integration.

## Limits before deployment

The service deliberately binds to loopback. Keep it local until HTTPS,
reverse-proxy timeouts/request limits, backup/restore, migrations, rate limiting
across processes, observability and operational review are completed. Standard
http.server is not an internet-facing production server. Browser CORS is not
enabled; native clients or a same-origin development proxy can be used initially.

Auth attempts are limited to ten per IP per minute in one process. Password
reset, email verification, refresh tokens, device management, OAuth, social
account lookup and authorization roles are not implemented. Public comments
are readable without login and username is displayed. There is no spam/content
moderation enforcement beyond reporting and owner checks. Comment deletion
redacts text but retains the thread tombstone.

Library stores only the last resume pointer per content item. An older episode
update replaces that pointer; this API cannot yet import or synchronize the
client's complete per-episode history. An offline stale PATCH after DELETE
recreates the item, so enable sync only after selecting a conflict policy or
adding base-revision checks. It is not an all-episode completion ledger. History-duration statistics, offline conflict UI, account
deletion/export, retention/cleanup of operation records, SQL migrations and
durable cross-process caching are follow-up work. SQLite transactions serialize
writes in this one process; no multi-worker guarantees are claimed.

Tests use an in-memory SQLite database and injected synthetic gateway responses.
HTTP tests bind an ephemeral loopback port only. No real tokens or external
network calls are needed. **Tests have not been executed in the current editing
session** because a Python execution tool was unavailable; run the command above
before integration. No Flutter tests or live playback checks were performed.
