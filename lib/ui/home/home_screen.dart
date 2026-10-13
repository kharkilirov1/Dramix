import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../filter/filter_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../widgets.dart';

/// Главная: search bar, tabs
/// Моя вкладка / Последнее / Онгоинги / Анонсы / Завершенные and the release list.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    return SafeArea(
      bottom: false,
      child: Column(
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
