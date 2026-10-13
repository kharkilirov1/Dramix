# Optional owned catalog gateway

The Flutter client can now call the local server prototype for catalog requests.
In Settings → «Свой сервер каталога», enter the **origin** of your trusted server:
`https://dramix.example` or, for same-device development,
`http://127.0.0.1:8080`. The setting is also available on the startup token-error
screen. Do not enter /v1, provider tokens, passwords or query parameters.
Clear the field to return to the existing direct/proxy guest route.

This routes list/search/translations to /v1/catalog/*. The client sends no Kodik
token, does not validate/rotate community tokens, bypasses public CORS proxies,
refuses redirects and does not fall back to Kodik on a server error. The server
needs KODIK_TOKEN configured locally. Pagination keeps filters and forwards
next_cursor as next; provider next_page URLs are discarded.

HTTPS is required except for loopback development. A physical phone's loopback
address points to that phone, not your development PC. HTTPS browser builds
cannot call an HTTP server through mixed-content rules; configure HTTPS and
explicit server CORS origins for browser use. This patch does not deploy a server
or relax platform network restrictions.

Only catalog routing is integrated: playback remains the existing Kodik player,
and library/history remain local. Account sessions, synchronization and comments
are not wired into Flutter yet. Direct guest mode remains the default.

Synthetic MockClient coverage is in test/backend_gateway_test.dart; no live
provider requests or real credentials are needed. Run flutter test and flutter
analyze before release. Tests were not executed during this editing session
because no Flutter runtime was available.
