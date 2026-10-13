# Playback provider contract and Kodik evidence

Only the Kodik adapter is implemented. FrameXTV was a design reference, not a
content source or a protocol authority. No extractor, WASM/crypto service,
direct-link resolver or new fallback provider is added.

## Evidence status

Checked 2026-10-13 without API tokens, authenticated player pages or playback:

- [Kodik's public root](https://kodikplayer.com/) is reachable but only presents
  contact/access information. It does **not** document playback events.
- [The official documentation host](https://bd.kodikres.com/player/api) was not
  accessible through the available reader. Official current behavior is unverified.
- [ShikiPlayer consumer implementation, pinned revision](https://github.com/Onzis/ShikiPlayer/blob/51af68c221fadb7c49d2e42480c3fcb74cab5f94/ShikiPlayer.user.js)
  checks iframe source, parses JSON strings and consumes the numeric
  kodik_player_time_update value. This is primary evidence of that project's
  integration, not a guarantee from Kodik.
- [AnimeWatch consumer event definitions, pinned revision](https://github.com/SunriseD232/AnimeWatch/blob/7c8930bfa4038fd24a2ad71a61d02d3d0c8430a2/src/lib/video/kodik-events.ts)
  corroborate time/duration, play/pause, video-start/end and episode messages.
- [Third-party documentation mirror, pinned revision](https://github.com/track-anime/track-anime.github.io/blob/a9dee7e5ddb95116f1845c47505c46fb40552657/docs/kodik-api/player-api.md)
  describes key/value envelopes, seconds for time/duration, seek's time field,
  episode coordinates and movie null coordinates. Its attribution to Kodik is
  the mirror author's claim; it was not independently compared to official docs.
- [AnimeParsers catalog notes](https://github.com/YaNesyTortiK/AnimeParsers/blob/main/KODIK_API.md)
  show kodik.info player links, and
  [kodikwrapper's README](https://github.com/thedvxch/kodikwrapper/blob/master/README.md)
  shows aniqit.com links. Those two aliases are explicit configuration based on
  public integrations, not a fresh availability check.

These corroborated third-party schemas are implemented conservatively and must
be checked against real approved player sessions before release. Capabilities
mean the adapter understands that protocol, not that a given platform/player
emitted it. Inbound control/seek commands are deliberately absent and resumeSeek
is false, despite community examples describing controls.

## Adapter API

PlaybackProvider exposes identity, protocol capabilities, supportsFrameUri and
openSession. Unsupported URLs receive no Kodik session or confirmed telemetry.
Kodik accepts only HTTPS default-port links with no userinfo from the explicit
kodikplayer.com/kodik.info/aniqit.com host set; no subdomain/wildcard trust.

A session binds an exact selected iframe origin, random local session ID,
caller epoch, stable selected episode key and season/episode, plus an optional known translation ID. Call
parseMessage(payload, origin, sourceVerified, epoch, episodeKey, sequence)
only after authenticating the platform sender:

- Web compares MessageEvent.source with the current iframe.contentWindow.
- Native injects the bridge solely in its main wrapper document, compares the
  message source with that wrapper's actual iframe and uses an unpredictable
  private nonce in its Dart bridge envelope. Nonce/session matching happens
  before this parser. A provider-controlled sourceVerified field is not proof.
- The caller supplies epoch/episodeKey and a monotonically increasing local
  sequence; these are never read from the provider payload.

The parser enforces origin, local context and sequence, accepts bounded JSON
strings or maps, then emits typed play/pause/time/duration/seek/ended events.
Unknown names and generic FrameXTV/PlayerJS messages are rejected. Numeric
seconds must be finite, nonnegative and at most seven days; numeric strings and
booleans are not coerced. Milliseconds are rounded once at the adapter boundary.

An embedded current_episode or expected translation mismatch emits episodeChanged and suspends further
playback telemetry until the selected coordinates are reported again. isSuspended lets the embed block native stream takeover too. The app
must also suspend its tracker when it receives that event; it must not persist
another iframe-selected series under the previous episode. Malformed episode
coordinates suspend parsing rather than silently retaining an attribution.
Null coordinates are allowed only with explicit isMovie=true and bound 1/1.

Initially attribution comes from the selected episode's catalog URL and trusted
embed lifetime. A provider that internally switches episodes without announcing
it cannot be detected from time alone; this is an external protocol limitation.

## Progress semantics and verification

Time or seek alone never proves playback or elapsed watched time. Duration is
metadata. The progress tracker must require confirmed play and attribute samples
only to its current session/episode. A seek is a checkpoint change, not watched
duration. Page load/iframe readiness and requested autoplay are not play events.

Eleven adapter tests cover host/origin/source/context rejection, JSON decoding,
sequence replay, numeric bounds, separate seek semantics, embedded episode
and translation switching, unknown payloads, movie context and actual event names. The generic error kind is available for
trusted native/platform failure signals; no unverified Kodik error key is parsed. Fixtures are
synthetic. Tests/analyzer were not run locally because the current session has
no Dart runtime; integration CI must run them. No live playback was exercised.
