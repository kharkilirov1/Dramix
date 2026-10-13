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

  /// Ids in the local history, used by «скрыть просмотренное».
  Set<String> _watched = const <String>{};

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
    final ids = await Library.watchedTitleIds();
    if (mounted) setState(() => _watched = ids);
  }

  Future<void> _loadMyTab() async {
    final saved = await Library.myTabFilter();
    if (!mounted) return;
    setState(() {
      _myTabFilter = saved;
      _loadingMyTab = false;
    });
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
    await Library.setMyTabFilter(picked);
    if (!mounted) return;
    setState(() {
      _myTabFilter = picked;
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
    final filter = _filterFor(_tab);
    if (filter == null) return _emptyMyTab();
    final needsClientFilter = filter.minRating != null || filter.hideWatched;
    return PagedScroll(
      key: ValueKey(filter.signature),
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

  Widget _shelf(BuildContext context, String title, CatalogFilter filter) {
    return CatalogShelf(
      key: ValueKey(filter.signature),
      heading: title,
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
          child: Wrap(spacing: 10, runSpacing: 8, children: [
            SizedBox(
              width: 190,
              child: LightPillButton(
              label: 'Весь каталог',
              icon: Icons.grid_view_rounded,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const CatalogScreen(),
              )),
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.tune),
              label: const Text('Фильтр'),
              onPressed: () async {
                final filter = await Navigator.of(context).push<CatalogFilter>(
                  MaterialPageRoute(builder: (_) => const FilterScreen()),
                );
                if (!context.mounted || filter == null) return;
                _results(context, filter);
              },
            ),
          ]),
        ),
        const ContinueWatchingShelf(),
        _shelf(context, 'Недавно обновлённые', recent),
        _shelf(context, 'Сериалы с высоким рейтингом', popular),
        _shelf(context, 'Корейские дорамы', korean),
        _shelf(context, 'Мелодрамы', romantic),
        const SizedBox(height: 24),
      ]),
    );
  }
}
