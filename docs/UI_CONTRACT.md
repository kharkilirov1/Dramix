# UI contract — Dramix

Dramix uses the **Kodik** drama/series catalog. The owner has authorized a
**gradual Netflix-inspired discovery UI**, retaining the four navigation tabs,
local library and guest access. Anixart styling is a starting point rather than
a requirement to reproduce its screens one-to-one. Read this before writing any screen.


## Дополнительный референс: FrameXTV

Источник, предоставленный владельцем: https://framextv.xyz/
Изучены структура главной, каталог TV, страница Reacher и публичная документация
API плеера. Использовано текстовое извлечение страниц; визуальный рендер,
мобильная адаптация и фактическое воспроизведение не проверены.

Подходящие направления для Dramix:
- выделенный тайтл с описанием и действиями просмотра/подробностей;
- подборки по популярности, обновлениям и жанру с переходом «Все»;
- переключение каталога между полками и сеткой;
- явно выбранный сезон, количество серий и карточки отдельных эпизодов;
- близкие по жанру/стране произведения при наличии данных;
- быстрый доступ к личному списку и истории.

Приоритеты сохраняются: локальное продолжение, выбор сезонов и озвучки,
библиотека и гостевой доступ. Выделенная панель, если добавляется, статичная;
не обещать даты выхода, кадры/описания каждой серии или рекомендации,
которые не предоставлены источником данных. Глобальную популярность и
персональные рекомендации обозначать различимо.

Публичная документация FrameXTV описывает старт с timestamp и события
`frameXTV:timeupdate` через `postMessage`, а также fallback провайдеров.
Это полезный образец контракта собственного playback bridge, а не
подтверждение аналогичной поддержки Kodik. Перед применением проверить
реальные события, source/origin сообщений и привязку к текущей серии;
сохранять ограничения прогресса iframe до подтверждённой интеграции.

Проверенные страницы:
- https://framextv.xyz/
- https://framextv.xyz/tv
- https://framextv.xyz/tv/108978
- https://framextv.xyz/api

## Design language (evolve existing components gradually)

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

Use existing colors and shared components. Home/discover use one vertical page
scroll and horizontal poster shelves; keep responsive sizing and text scaling.
Sub-pages use `PageScaffold`. No autoplay hero or replacement of library navigation.

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
Library.continueWatching({int limit = 12}) // newest positive checkpoint per work
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

Kodik is a video catalog, not a community. Wire visible features to real data:

- **Главная** — search for dramas/series, local «Продолжить просмотр»,
  finite shelves «Недавно обновлённые», «Сериалы с высоким рейтингом»,
  «Корейские дорамы», «Мелодрамы». Network sections load and retry independently.
  «Все» opens the existing paginated results; «Весь каталог» opens CatalogScreen
  with the old catalog tabs and saved custom filter. Lists/favorites are preserved.
- **Обзор** — serial-focused banners, existing navigation tiles and finite
  «Сейчас выходят» shelf. No claims of personalization without an actual algorithm.
  Collections are genre/country queries, not user-curated social lists.
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
4. Keep full list feeds wrapped in `PagedScroll` with a `ValueKey(signature)`.
   Finite poster shelves use independent loaders and a route to full results.
5. Handle the three states every time: loading, error (`ErrorCentered` with
   `onRetry`), empty.
6. Kodik has **no** user accounts, comments, friends or airing calendar —
   do not fake them. Local data comes from `Library`. Where a reference screen
   has no Kodik equivalent, adapt or remove the placeholder and honestly state the situation.
7. Verify with `flutter analyze` before finishing.

## Playback and local library

Shelf progress only identifies the saved season/episode and opens its title
card. It does not promise automatic seeking inside a third-party iframe.
Native video can restore a known checkpoint; iframe progress requires reliable
player events and must never be inferred from page loading.

No account is required. Comments and cloud sync are future server features,
not placeholders described as working features. Canonical identity is
conservative: only known external IDs link translations; never title/year guesses.

## Verification for the home adaptation

Before merge run formatter, analyzer and Flutter tests, including
`test/home_shelves_test.dart`. Test narrow mobile and wide desktop/web layouts,
text scaling, independent section failures, clearing history, shelf deduplication
across registered translations, and complete catalog pagination.
These checks have not been executed in the editing session.
