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
| PATCH /v1/library | partial update/import with required base_revision |
| GET /v1/checkpoints?after=0&limit=100 | authenticated episode checkpoint changes; optional work_key |
| DELETE /v1/library | work_key/base_revision; item and episode tombstones |
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
  "base_revision": 0,
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
checkpoint, not proof of completion or accumulated watch duration. Updating
progress saves that season/episode checkpoint durably and separately updates
the last-resume pointer. Updating one episode never erases another checkpoint.
Clearing progress clears only the last-resume pointer, not episode history.

work_key is an **opaque stable content ID** supplied by the client. Suggested
namespaces matching the Flutter identity work: kinopoisk:<positive digits>,
imdb:tt<digits>, mdl:<positive digits>, shikimori:<positive digits>, fallback
kodik:<provider-record-id>. The server never merges names/years, discovers
aliases or replaces a provider playback ID. variant_id remains separate;
checkpoint identity is user + work_key + season + episode, and variant_id
describes the latest saved rendition of that episode.

Every library PATCH and DELETE requires **base_revision**: use 0 only for a
never-created item; otherwise use its current revision from library sync.
Comparison and all writes occur in one SQLite transaction. A stale revision
returns 409 without altering library/checkpoints or recording a successful
operation. Pull changes and resolve the conflict deliberately, then submit
a new operation with a new Idempotency-Key and the current base_revision.
Retrying an already successful request with its original key/body returns
the old response without repeating writes, even if the item has since changed.

DELETE emits a library tombstone and a tombstone for every active checkpoint.
An ordinary PATCH cannot recreate a deleted item even with its latest revision.
An intentional recreation requires restore=true AND the current tombstone
base_revision; it restores only explicitly supplied fields/checkpoints.
Older checkpoint tombstones remain, so history is not silently resurrected.

Sync returns current snapshots changed since after, including tombstones.
Keep polling while has_more is true; persist the returned cursor only after
applying that page. Library and checkpoint feeds have **independent cursors**.
Do not advance a cursor using a mutation response: other updates may exist
before its revision. An idempotent replay can return an older response; do not
apply it over a newer local revision. Keep the same optional work_key filter
for a checkpoint cursor, or restart from 0 when switching filters.

## Import existing on-device history

A library PATCH may contain checkpoints: an array of at most 100 unique
season/episode checkpoint objects, using the same position_ms/variant_id format
as progress. All imported points and library metadata share the same
base_revision check, transaction and idempotency key. Supply progress separately
to choose the last-resume pointer; the server does not guess it from episode
number or array order. A checkpoints-only import leaves the resume pointer
unchanged. Split larger histories into batches and use the resulting current
library revision for each next batch, with a new operation key.

1. Authenticate and fetch library/checkpoint snapshots with cursors starting at 0.
2. Resolve local provider IDs to stable work_key using the Flutter identity map.
   Do not merge titles by name/year. Group points per work_key and deduplicate
   season/episode explicitly; select the latest locally recorded checkpoint.
3. For a never-created work use base_revision=0. For an existing work review
   server data first and use its current revision. Do not silently overwrite
   server history or restore a tombstone during import.
4. Send checkpoints[] and optional favorite/status/rating/progress. Persist the
   request body and Idempotency-Key in the local outbox until success. On 409,
   fetch current state and ask/reconcile instead of blindly changing the base.
5. Poll both feeds and apply only revisions newer than the local stored ones.

SQLite schema version 2 is created automatically. Existing prototype databases
keep accounts/sessions/library and backfill their valid last-resume pointer
into the episode table once; they cannot recover older episode history that was
never uploaded. On-device history must be imported explicitly as above.

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
http.server is not an internet-facing production server.

### Flutter Web development

Browser CORS is disabled by default. To use the optional owned gateway from a
local Flutter Web build on port 8321, set
DRAMIX_ALLOWED_ORIGINS=http://localhost:8321 (or the exact 127.0.0.1 origin used).
Comma-separated origins are supported. HTTPS origins are permitted; HTTP is
restricted to localhost/127.0.0.1/::1. Wildcards, paths, userinfo and arbitrary
reflected origins are refused. OPTIONS permits only GET/POST/PATCH/DELETE and
Content-Type/Authorization/Idempotency-Key. Requests from other browser origins
return 403; native clients without Origin continue to work. Bearer tokens are
used explicitly; cookie credential sharing is not enabled.

Set the Flutter owned gateway base to http://127.0.0.1:8080 for native builds or
the reachable local server origin for Web. Catalog requests then use
/v1/catalog/list/search/translations and require no Kodik token in Flutter.
Account/library/checkpoint/comment mutations use the bearer session and revision
contract documented above. A backend connection does not by itself migrate
local accounts/history or change playback URLs.

Auth attempts are limited to ten per IP per minute in one process. Password
reset, email verification, refresh tokens, device management, OAuth, social
account lookup and authorization roles are not implemented. Public comments
are readable without login and username is displayed. There is no spam/content
moderation enforcement beyond reporting and owner checks. Comment deletion
redacts text but retains the thread tombstone.

Library and per-episode checkpoints are stored separately with optimistic
per-item revision checks. Checkpoints are not an episode-completion ledger or
accumulated watch-duration accounting. Client outbox, conflict UI and the actual
Flutter import/sync integration are still required. History-duration statistics, offline conflict UI, account
deletion/export, retention/cleanup of operation records, future schema migrations and
durable cross-process caching are follow-up work. SQLite transactions serialize
writes in this one process; no multi-worker guarantees are claimed.

Tests use an in-memory SQLite database and injected synthetic gateway responses.
HTTP tests bind an ephemeral loopback port only. No real tokens or external
network calls are needed. The current editing session has no local Python execution tool; GitHub Actions
CI is being added separately to run these checks before integration. No Flutter tests or live playback checks were performed.
