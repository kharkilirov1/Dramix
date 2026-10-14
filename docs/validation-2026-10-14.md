# Executed backend validation — 2026-10-14

Application source tested: `00a816603bcd7c420bf1ee1fc1371c476a7177c7`
(the UI-polish draft). The repository's 182 tracked files were transferred to an
execution sandbox and their Git blob SHA-1 values were checked before execution.

## Python server: passed

Runtime: Python 3.13.13. The backend source was not changed.

Command:

```sh
python3 -m unittest discover -s server -p 'test_*.py' -v
```

Final repeated run:

```text
Ran 23 tests in 4.290s

OK
```

Process exit code: 0. Execution evidence: `log_ikANXuhJWOwO`.

A separate HTTP smoke harness started the actual `ThreadingHTTPServer` handler
with SQLite and made 37 loopback HTTP requests. All 35 assertions passed.
There were 3 calls to a synthetic upstream provider. The checks exercised
accounts/sessions, user isolation, catalog/cursors, library revisions,
idempotency, episode checkpoints, deletion, comments/spoilers and CORS.

A further subprocess launched the actual `server/app.py` entrypoint:

| Check | Observed result |
|---|---|
| `GET /health` | 200 |
| Catalog without a configured server key | 503 |
| SQLite database creation | Passed |

The entrypoint process was stopped after testing. HTTP/entrypoint results were
repeated and reread before execution became unavailable:
`log_D2OsUHlFPtpR`. The separate smoke harness was temporary validation tooling;
the repository's reproducible suite is the unittest command above.

These are executed tests of the actual server, with fixture catalog responses.
Live Kodik, real provider credentials and production deployment were not tested.

## Flutter client: not executed

Flutter formatter, analyzer, widget tests and web build did not run.
The sandbox had about 985 MiB RAM; Flutter tool bootstrap from source was killed
for memory pressure. Subsequent shell and Jupyter calls failed with sandbox
execution errors, including after reconnect attempts.

The first archive lookup used an incorrect URL prefix. That address was
corrected, but the corrected archive download/availability could not be checked
after execution failed. Official Flutter source tag 3.24.5 and Dart 3.5.4 were
identified; this does not establish a working Flutter toolchain.

GitHub Actions for PR #8 also stopped before runner allocation and performed
zero steps. Keep the PR draft pending actual Flutter checks and device playback.

Logs were saved under `/home/user/dramix-validation-results` in the execution
sandbox. That sandbox is currently unavailable, so those paths are not
user-downloadable artifacts.
