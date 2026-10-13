# UI contract — Dramix

Dramix reproduces the **Anixart** client UI one-to-one, but is backed by the
**Kodik** drama catalog. Read this before writing any screen.

## Design language (do not invent new styles)

All tokens live in `lib/core/theme.dart` → `AppColors`:

| token | value | used for |
|---|---|---|
| `bg` | `#121212` | page background |
| `surface` | `#252525` | pills, search bar, nav, cards |
| `surfaceHigh` | `#2E2E2E` | raised cards |
| `outline` | `#3D3D3D` | dividers, outlined pill borders |
| `textPrimary` | `#F5F5F7` | titles |
| `textSecondary` | `#A1A1AA` | body/meta |
| `textTertiary` | `#71717A` | hints, inactive tabs |
| `accent` | `#4A4458` | active nav pill |
| `light` | `#E0E0E0` | light filled buttons |
| `badgeNew` | `#E53935` | "new" / destructive |
| `statWatching/Plans/Completed/HoldOn/Dropped` | green/violet/blue/orange/red | list-status colours |

Typography conventions from the reference client:
screen titles `21 w700`; section headings `19–20 w700`; list titles
`15.5 w600`; meta `12.5–13`; tabs `15` (`w700` active / `w400` inactive);
nav labels `12`.

Screens are **not** wrapped in a floating app bar: a plain
`SafeArea(bottom: false)` + `Column` with `TopBar` on top, exactly like the
reference. Sub-pages use `PageScaffold`.

## Shared widgets — `lib/ui/widgets.dart`

```dart
Poster({String? url, required double width, required double height, double radius = 10})

ReleaseListItem({required String title, String? image, double? grade,
    String meta = '', String? description, int? rank, VoidCallback? onTap})
ReleaseListItem.kodik(KodikTitle t, {int? rank, VoidCallback? onTap})
ReleaseListItem.saved(SavedTitleRef t, {VoidCallback? onTap})

UnderlineTabs({required List<String> tabs, required int selected,
    required ValueChanged<int> onChanged, double separator = 24})

BigPillButton({required IconData icon, required String label,
    VoidCallback? onTap, Widget? trailing})

LightPillButton({required String label, IconData? icon,
    bool loading = false, VoidCallback? onTap})

ErrorCentered({required String message, VoidCallback? onRetry})

PageScaffold({required String title, required Widget body,
    List<Widget> actions = const []})

/// Cursor-paginated Kodik list. Dedupes per-dubbing duplicates automatically.
PagedScroll({required Future<KodikPage> Function(String? cursor) loader,
    required Widget Function(BuildContext, KodikTitle, int index) itemBuilder,
    Widget? header, String emptyText = 'Здесь пока пусто',
    bool dedupe = true, EdgeInsets padding = EdgeInsets.zero})

/// Local (offline) list.
SavedList({required List<SavedTitleRef> items,
    required void Function(BuildContext, SavedTitleRef) onTap,
    String emptyText = 'Здесь пока пусто', Widget? header})

CollectionCard({required CuratedCollection collection, String? image,
    int? count, VoidCallback? onTap})

void showMessage(BuildContext context, String message);
String stripHtml(String s);
```

`lib/ui/root.dart` additionally exports:

```dart
TopBar({required String searchHint, VoidCallback? onSearch, int notificationBadge = 0})
class Routes { search, settings, notifications, popular, schedule,
               collections, collection, filter, release, voiceover }
```

## Data layer

### `lib/core/kodik_api.dart`

```dart
KodikApi.instance
  .fetch(CatalogFilter filter, {String? cursor, int limit = 30, bool withMaterial = true})
  .browseFiltered(CatalogFilter filter, {int limit = 30, bool withMaterial = true})
  .nextPage(String url)
  .search({required String query, String? types, int limit = 30, int? year,
           String? genres, bool withMaterial = true, bool strict = false})
  .byId(String id)            // full record incl. seasons/episodes
  .versions(KodikTitle)       // sibling records = alternative dubbings
  .randomTitle()
  .translations()
KodikApi.dedupe(Iterable<KodikTitle>)
class KodikApiException { int status; String message; }
```

`fetch(filter, cursor: cursor)` is the one to use with `PagedScroll`:

```dart
PagedScroll(
  key: ValueKey(filter.signature),                 // restarts pagination
  loader: (cursor) => KodikApi.instance.fetch(filter, cursor: cursor),
  itemBuilder: (context, title, index) =>
      ReleaseListItem.kodik(title, onTap: () => openTitle(context, title)),
)
```

> `PagedScroll` only reloads when its **key** changes — always pass
> `ValueKey(filter.signature)` (or the query string) so a new query restarts it.

### `lib/core/models.dart`

`CatalogFilter` — `types`, `allStatus`, `genres`, `countries`, `year`,
`minimalAge`, `sort`; plus `isEmpty`, `activeCount`, `copy()`, `signature`,
`toQuery()`, `toJson()`, `fromJson()`.

`KodikCatalog` — `dramas`, `movies`, `anime`, `cartoons`, `documentary`, `all`.
`DramaGenres.all` — the 20 genre names Kodik accepts (others silently return 0).
`DramaCountries.all` — `Корея Южная, Китай, Япония, Турция, Таиланд, США`.
`AiringStatus` — `ongoing` / `released` / `anons` (+ `.label`).
`CatalogSort` — `updated` / `rating` / `year` / `created` (+ `.label`).

`KodikTitle`: `id, type, title, titleRu, titleOrig, otherTitle, year, link,
episodesCount, quality, camrip, translation, material, seasons, screenshots,
createdAt, updatedAt` and getters `poster, image, grade, genres, genreList,
description, typeLabel, statusName, episodesLabel, totalEpisodes, isSerial,
dedupeKey, ref, episodeRefs, subtitle`.

`KodikMaterial`: `posterUrl, description, genres, countries, actors, directors,
duration, minimalAge, allStatus, episodesTotal, kinopoiskRating, imdbRating,
bestRating, ratingSource, countryLabel, screenshots`.

`KodikEpisodeRef { int season; int episode; String url; String get label; }`
`SavedTitleRef { id, title, poster, type, year, episodes, link, subtitle }`

### `lib/core/storage.dart` — all local, Kodik has no accounts

```dart
Library.revision                       // ValueNotifier<int>, bump => screens refresh
Library.history() / record(WatchEntry) / clearHistory() / resumePoint(id)
Library.favorites() / isFavorite(id) / toggleFavorite(SavedTitleRef) / clearFavorites()
Library.watchStatus(id) / setWatchStatus(SavedTitleRef, WatchStatus?)
Library.list(WatchStatus) / clearLists()
Library.stats()  -> LibraryStats
Library.searchHistory() / rememberSearch(q) / clearSearchHistory()
Library.myTabFilter() / setMyTabFilter(CatalogFilter?)

enum WatchStatus { watching, plans, completed, holdOn, dropped }  // .value .title
class WatchEntry { SavedTitleRef title; int? season, episode; int positionMs; DateTime watchedAt; String get label; }
class LibraryStats { int watchedEpisodes, watchedSeconds, watchedDays, favorites, historySize;
                     int countFor(WatchStatus); }
```

`WatchStatus.title` → `Смотрю / В планах / Просмотрено / Отложено / Брошено`,
matching the reference client's tab order.

### `lib/core/collections.dart`

```dart
Curated.all : List<CuratedCollection>     // 14 curated sets
Curated.byId(String id)
CuratedCollection { String id, title, subtitle; CatalogFilter get filter; String get signature; }
```

## Screens to implement

| file | public API |
|---|---|
| `lib/ui/home/home_screen.dart` | `HomeScreen()` |
| `lib/ui/discover/discover_screen.dart` | `DiscoverScreen()` |
| `lib/ui/bookmarks/bookmarks_screen.dart` | `BookmarksScreen()` |
| `lib/ui/profile/profile_screen.dart` | `ProfileScreen()` |
| `lib/ui/search/search_screen.dart` | `SearchScreen()`, `FilteredResultsScreen({required CatalogFilter filter})` |
| `lib/ui/filter/filter_screen.dart` | `FilterScreen()` → pops `CatalogFilter?` |
| `lib/ui/settings/settings_screen.dart` | `SettingsScreen()` |
| `lib/ui/popular/popular_screen.dart` | `PopularScreen()` |
| `lib/ui/schedule/schedule_screen.dart` | `ScheduleScreen()` |
| `lib/ui/collections/collections_screen.dart` | `CollectionsScreen()`, `CollectionDetailScreen({required CuratedCollection collection})` |
| `lib/ui/notifications/notifications_screen.dart` | `NotificationsScreen()` |

Provided elsewhere — **do not reimplement**:

```dart
// lib/ui/release/title_screen.dart
Future<void> openTitle(BuildContext context, KodikTitle title);
/// Opens a title from a locally stored snapshot (history / favourites / lists).
Future<void> openSavedTitle(BuildContext context, SavedTitleRef ref);
class TitleScreen({required KodikTitle title});
class VoiceoverScreen({required KodikTitle title});

// lib/ui/player/player_screen.dart
class PlayerScreen({required KodikTitle title,
                    required List<KodikEpisodeRef> episodes,
                    int initialIndex = 0});
```

## Screen-by-screen mapping (agreed behaviour)

Kodik is a video catalog, not a community. Keep the reference layout, but wire
it to what the data actually supports:

- **Главная** — `TopBar('Поиск дорам')` + `UnderlineTabs(['Моя вкладка',
  'Последнее', 'Онгоинги', 'Анонсы', 'Завершенные'])`, default index `1`.
  Tab 0 reads `Library.myTabFilter()`; when it is `null`, show the reference's
  empty state with a `LightPillButton('Открыть Фильтр')` that pushes
  `FilterScreen` and stores the result via `Library.setMyTabFilter`.
  Tabs 1–4: `sort: updated`, `allStatus: 'ongoing'`, `'anons'`, `'released'`.
- **Обзор** — image banners from the top-rated list, the five `BigPillButton`
  tiles (Популярное / Расписание / Коллекции / Фильтр / Рандом), the
  «Рекомендации» card, and instead of «Обсуждаемое сегодня» a «Сейчас выходят»
  feed (`allStatus: 'ongoing'`).
- **Закладки** — the eight underline tabs in the reference order. «Коллекции»
  renders `Curated.all` with `CollectionCard`; every other tab is local data
  through `Library`, and the screen listens to `Library.revision`.
- **Профиль** — reference layout, local numbers from `Library.stats()`; the
  donut chart uses `fl_chart`'s `PieChart` over the watch-list distribution.
- **Расписание** — Kodik has no airing calendar. Group the recently updated
  feed by weekday of `KodikTitle.updatedAt`, keep the reference's Пн–Вс tabs,
  and say honestly in the subtitle what the screen shows.
- **Уведомления** — Kodik has no notification feed. Show «Недавно обновлённые»
  (`sort: updated`) with the reference chrome.
- **Анонсы** is genuinely empty for dramas — render the standard empty state.

## Ground rules

1. **No new dependencies** beyond those already in `pubspec.yaml`:
   `flutter`, `http`, `shared_preferences`, `cached_network_image`,
   `video_player`, `webview_flutter`, `fl_chart`.
2. **`flutter analyze` must stay at 0 issues.** `flutter_lints` is on:
   prefer `const` constructors, no unused imports/fields, no
   `print` outside `// ignore: avoid_print`.
3. All user-facing text is **Russian**, matching the reference wording
   (`Здесь пока пусто`, `Повторить`, `Войдите…` etc. as appropriate).
4. Keep list feeds wrapped in `PagedScroll` with a `ValueKey(signature)`.
5. Handle the three states every time: loading, error (`ErrorCentered` with
   `onRetry`), empty.
6. Kodik has **no** user accounts, comments, friends or airing calendar —
   do not fake them. Local data comes from `Library`. Where a reference screen
   has no Kodik equivalent, keep the reference layout and honestly state the
   situation (e.g. an empty state with an explanatory line).
7. Verify with `flutter analyze` before finishing.
