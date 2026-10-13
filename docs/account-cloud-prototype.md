# Optional account and cloud import prototype

AccountScreen requires a configured backend origin. BackendSession.forOrigin
provides the in-memory session shared with comments. Always call forOrigin with
the current Net.backendOrigin before injecting token/userId callbacks: a changed
origin destroys the previous session, and credentials must never be forwarded
to a different origin.

Bearer tokens/passwords are not persisted. Restart requires sign-in. The
prototype intentionally has no secure-storage/refresh-token claim.

Signing in does not upload local data. Explicit pull fetches both full paginated
feeds into one account- and origin-scoped JSON snapshot. Tombstones are retained.
Snapshots do not replace guest library/history, and mutation acknowledgements
do not advance a feed cursor or overwrite newer snapshots.

Explicit import first pulls cloud state and rejects existing works, including
tombstones. It backs up original guest keys once per account/server, then stores
the exact body and random idempotency key before any write. Retry uses that body
and key unchanged. Network failures and 409 retain pending operations. No
automatic revision rebasing or resurrection occurs. Each work is one atomic
server PATCH; the entire library import is not a single transaction. Records
with more than 100 episode checkpoints are rejected before any writes.

Guest keys are never removed or rewritten. Ratings associated only with an
otherwise absent title cannot currently be imported because they have no saved
title reference. Legacy history without positive season/episode is not guessed
into a checkpoint. Cloud data can be counted/inspected by the prototype but is
not merged into the active on-device Library.

Not implemented: background sync, continuous offline queue for guest mutations,
manual per-field conflict resolution, restore/delete UI, applying cloud library
to existing views, secure persisted sessions. A 409 requires a future deliberate
reconciliation UI; do not retry with a guessed new revision.

Tests use MockClient and SharedPreferences mocks, with no real network/secret.
Flutter runtime/analyzer were unavailable during editing; CI must validate.

Legacy invalid episode points are counted and reported by the import panel. Their
raw guest data remains in the immutable backup. Works with no valid importable
fields are not queued, avoiding permanent empty PATCH failures.
