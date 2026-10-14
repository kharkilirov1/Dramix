# Dramix UI polish

Prepared 2026-10-14 on top of the provider-event draft (#7).

## Result

- Home prioritizes local continuation and adds a static featured title from
  recently updated Kodik results. Shelves retain independent loading and retry.
  Ratings name their source; no fabricated percentages or personalization.
- Drama details adapt to wide and narrow screens. Seasons and episode numbers
  remain distinct; the primary action follows the available saved episode or
  selected season. A local-history failure does not block available video.
- History, favorites and watch lists use working local search/sorting and one
  scrolling layout. Checkpoints display saved position, season, episode and date.
  Clearing history requires confirmation and only affects this device.
- Search cannot resurrect a reset query after asynchronous storage completes.
  Countries/genres open one multi-select sheet. Hidden watched items refresh
  when local history changes, after their IDs have finished loading.
- Discovery and update views describe catalog results honestly. Weekday groups
  are a sample of recent updates, not an airing calendar. Collection descriptions
  reflect their queries; provider totals are not unique-title counts.
- Profile and account screens separate guest/local data from the optional
  server prototype. Checkpoints are not called completed episodes. Imports and
  cloud pulls remain explicit; there is no automatic two-way synchronization.
- Shared controls support text scaling, wrap metadata and expose keyboard/tap
  targets. Inert menus are removed. Settings catch failures and prevent repeat
  operations; credential fragments are not shown in the status.

Kodik remains the content provider. FrameXTV is only a design reference.
No FrameXTV providers, extractors, tokens or media services are connected.

## Verification status

Agents reviewed each other's changes and corrected findings before assembly.
Regression tests were added for responsive layout, navigation, query races,
filter refresh, local history clearing, playback actions and optional account
states. Flutter formatter, analyzer and tests have **not run** in this editing
environment: no usable execution runtime is available. Earlier repository
Actions attempts stopped before runner allocation, without executing a step.
Keep the draft unmerged until those checks and real-device playback pass.

No screenshot or rendered app preview was produced here. Code review alone
does not verify actual layout or current third-party iframe event behavior.

## Before merge

Run the existing repository workflow, then check:

1. A 320px-wide phone and a wide desktop, at default and 2x text scaling; open
   the keyboard in search/library and check landscape player controls.
2. Home: one failed feed can retry while other shelves remain available;
   continuation disappears after confirmed local history clearing.
3. Full catalog and search: paginate, switch categories, reset an in-flight
   search, apply a country/genre selection and return after watching an item.
4. Details: select a season, change rendition, retry a failed metadata request;
   missing saved episodes fall back to an available selected season.
5. History/lists: filter and sort, cancel/confirm clearing, verify favorites and
   optional server data are preserved.
6. Optional account: remain a guest, sign in to a configured local test server,
   cancel an import, inspect a conflict, and sign out during a pending operation.
7. Kodik iframe: play, pause, switch an embedded episode and reopen the intended
   episode in Dramix. A changed iframe episode must not pollute the old history.
8. Settings: cancel destructive dialogs; an invalid backend address preserves
   the previous routing. Exact iframe timestamp restoration is not promised.
