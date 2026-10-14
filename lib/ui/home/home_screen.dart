import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../filter/filter_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../widgets.dart';
import '../search/search_screen.dart';
import 'home_shelves.dart';

/// Full cursor-paginated catalog and saved custom filter.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  /// "Последнее" is active by default, exactly like the reference client.
  int _tab = 1;

  CatalogFilter? _myTabFilter;
  bool _loadingMyTab = true;
  bool _myTabFailed = false;

  /// Ids in the local history, used by «скрыть просмотренное».
  Set<String> _watched = const <String>{};
  bool _watchedReady = false;
  bool _watchedFailed = false;
  int _watchedRequest = 0;
  int _watchRevision = 0;

  @override
  void initState() {
    super.initState();
    Library.revision.addListener(_onLibraryChanged);
    _loadMyTab();
    _loadWatched();
  }

  @override
  void dispose() {
    Library.revision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) _loadWatched();
  }

  Future<void> _loadWatched() async {
    final request = ++_watchedRequest;
    final revision = Library.revision.value;
    try {
      final ids = await Library.watchedTitleIds();
      if (!mounted || request != _watchedRequest) return;
      setState(() {
        if (!_watchedReady || ids.length != _watched.length ||
            !ids.every(_watched.contains)) {
          _watchRevision = revision;
        }
        _watched = ids;
        _watchedReady = true;
        _watchedFailed = false;
      });
    } catch (_) {
      if (!mounted || request != _watchedRequest) return;
      setState(() {
        _watchedReady = false;
        _watchedFailed = true;
      });
    }
  }

  Future<void> _loadMyTab() async {
    setState(() {
      _loadingMyTab = true;
      _myTabFailed = false;
    });
    try {
      final saved = await Library.myTabFilter();
      if (!mounted) return;
      setState(() {
        _myTabFilter = saved;
        _loadingMyTab = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMyTab = false;
        _myTabFailed = true;
      });
    }
  }

  /// The catalog query for a tab. `null` for an unconfigured «Моя вкладка».
  CatalogFilter? _filterFor(int tab) {
    switch (tab) {
      case 0:
        return _myTabFilter?.copy();
      case 2:
        return CatalogFilter(sort: CatalogSort.updated)
          ..allStatus = AiringStatus.ongoing.value;
      case 3:
        return CatalogFilter(sort: CatalogSort.updated)
          ..allStatus = AiringStatus.anons.value;
      case 4:
        return CatalogFilter(sort: CatalogSort.updated)
          ..allStatus = AiringStatus.released.value;
      case 1:
      default:
        return CatalogFilter(sort: CatalogSort.updated);
    }
  }

  Future<void> _openFilter() async {
    final picked = await Navigator.push<CatalogFilter>(
      context,
      MaterialPageRoute(
          builder: (_) => FilterScreen(initial: _myTabFilter)),
    );
    if (picked == null) return;
    try {
      await Library.setMyTabFilter(picked);
    } catch (_) {
      if (mounted) showMessage(context, 'Не удалось сохранить фильтр');
      return;
    }
    if (!mounted) return;
    setState(() {
      _myTabFilter = picked;
      _myTabFailed = false;
      _loadingMyTab = false;
      _tab = 0;
    });
  }

  Widget _emptyMyTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Настройте свою вкладку через Фильтр',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 14),
            LightPillButton(label: 'Открыть Фильтр', onTap: _openFilter),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_tab == 0 && _loadingMyTab) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.textSecondary),
      );
    }
    if (_tab == 0 && _myTabFailed) {
      return ErrorCentered(
          message: 'Не удалось прочитать фильтр', onRetry: _loadMyTab);
    }
    final filter = _filterFor(_tab);
    if (filter == null) return _emptyMyTab();
    if (filter.hideWatched && !_watchedReady) {
      if (_watchedFailed) {
        return ErrorCentered(
            message: 'Не удалось прочитать историю', onRetry: _loadWatched);
      }
      return const Center(child: CircularProgressIndicator());
    }
    final needsClientFilter = filter.minRating != null || filter.hideWatched;
    return PagedScroll(
      key: ValueKey('${filter.signature}:'
          '${filter.hideWatched ? _watchRevision : 0}'),
      loader: (cursor) => KodikApi.instance.fetch(filter, cursor: cursor),
      accept: needsClientFilter
          ? (title) => filter.accepts(title, watched: _watched)
          : null,
      itemBuilder: (context, title, _) => ReleaseListItem.kodik(
        title,
        onTap: () => openTitle(context, title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Каталог',
      body: Column(
        children: [
          TopBar(
            searchHint: 'Поиск дорам',
            onSearch: () => Navigator.pushNamed(context, Routes.search),
          ),
          UnderlineTabs(
            tabs: const [
              'Моя вкладка',
              'Последнее',
              'Онгоинги',
              'Анонсы',
              'Завершенные',
            ],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}

/// Home focuses on resuming and discovering series; the complete catalog
/// remains one tap away, without requiring a user account.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _results(BuildContext context, CatalogFilter filter) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FilteredResultsScreen(filter: filter),
    ));
  }

  Widget _shelf(BuildContext context, String title, CatalogFilter filter,
      {String? subtitle, bool featured = false}) {
    return CatalogShelf(
      key: ValueKey(filter.signature),
      heading: title,
      subtitle: subtitle,
      featured: featured,
      loader: () async {
        final page = await KodikApi.instance.browseFiltered(filter, limit: 18);
        return KodikApi.dedupe(page.results);
      },
      onSeeAll: () => _results(context, filter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recent = CatalogFilter(types: KodikCatalog.dramas);
    final popular = CatalogFilter(
        types: KodikCatalog.dramas, sort: CatalogSort.rating);
    final korean = CatalogFilter(
        types: KodikCatalog.dramas, sort: CatalogSort.rating)
      ..countries.add('Корея Южная');
    final romantic = CatalogFilter(
        types: KodikCatalog.dramas, sort: CatalogSort.rating)
      ..genres.add('мелодрама');
    return SafeArea(
      bottom: false,
      child: ListView(children: [
        TopBar(
          searchHint: 'Поиск дорам и сериалов',
          onSearch: () => Navigator.pushNamed(context, Routes.search),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(builder: (context, constraints) {
            final catalog = FilledButton.icon(
              label: const Text('Весь каталог'),
              icon: const Icon(Icons.grid_view_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.light,
                foregroundColor: Colors.black,
                minimumSize: const Size(0, 48),
              ),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const CatalogScreen(),
              )),
            );
            final filter = OutlinedButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Фильтр'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                side: const BorderSide(color: AppColors.outline),
              ),
              onPressed: () async {
                final picked = await Navigator.of(context).push<CatalogFilter>(
                  MaterialPageRoute(builder: (_) => const FilterScreen()),
                );
                if (!context.mounted || picked == null) return;
                _results(context, picked);
              },
            );
            if (constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [catalog, const SizedBox(height: 8), filter],
              );
            }
            return Wrap(spacing: 10, runSpacing: 8, children: [catalog, filter]);
          }),
        ),
        const ContinueWatchingShelf(),
        _shelf(context, 'Недавно обновлённые', recent,
            subtitle: 'Последние изменения в каталоге', featured: true),
        _shelf(context, 'Сериалы с высоким рейтингом', popular,
            subtitle: 'По оценкам Кинопоиска'),
        _shelf(context, 'Корейские дорамы', korean,
            subtitle: 'Сериалы из Южной Кореи'),
        _shelf(context, 'Мелодрамы', romantic,
            subtitle: 'Жанр: мелодрама'),
        const SizedBox(height: 24),
      ]),
    );
  }
}
