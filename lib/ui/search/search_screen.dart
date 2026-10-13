import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../filter/filter_screen.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Поиск: back, поле с кнопкой запуска, фильтр каталога, история и результаты.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const List<String> _scopeLabels = <String>[
    'Дорамы',
    'Фильмы',
    'Аниме',
    'Всё',
  ];

  static const List<String> _scopeTypes = <String>[
    KodikCatalog.dramas,
    KodikCatalog.movies,
    KodikCatalog.anime,
    KodikCatalog.all,
  ];

  final TextEditingController _controller = TextEditingController();

  int _scope = 0;
  bool _searched = false;

  /// Committed query — only replaced by [_run] / [_reset], never in `build`.
  String _q = '';

  List<String> _history = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await Library.searchHistory();
    if (!mounted) return;
    setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    await Library.clearSearchHistory();
    if (!mounted) return;
    setState(() => _history = const <String>[]);
  }

  Future<void> _run() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    await Library.rememberSearch(q);
    final list = await Library.searchHistory();
    if (!mounted) return;
    setState(() {
      _q = q;
      _searched = true;
      _history = list;
    });
  }

  void _reset() {
    _controller.clear();
    setState(() {
      _searched = false;
      _q = '';
    });
  }

  void _useHistory(String q) {
    _controller.text = q;
    _run();
  }

  Future<void> _openFilter() async {
    final picked = await Navigator.push<CatalogFilter>(
      context,
      MaterialPageRoute(builder: (_) => const FilterScreen()),
    );
    if (!mounted || picked == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FilteredResultsScreen(filter: picked)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            child: Row(children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: AppColors.textPrimary),
                  onPressed: () {
                    if (_searched || _controller.text.isNotEmpty) {
                      _reset();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  }),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                      hintText: 'Поиск дорам',
                      hintStyle: TextStyle(color: AppColors.textTertiary),
                      border: InputBorder.none),
                  onSubmitted: (_) => _run(),
                ),
              ),
              IconButton(
                  tooltip: 'Найти',
                  icon:
                      const Icon(Icons.search, color: AppColors.textSecondary),
                  onPressed: _run),
              IconButton(
                  tooltip: 'Фильтр каталога',
                  icon: const Icon(Icons.tune, color: AppColors.textSecondary),
                  onPressed: _openFilter),
            ]),
          ),
          const Divider(height: 1, color: AppColors.outline),
          SizedBox(
            height: 44,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                const SizedBox(width: 16),
                for (final (i, label) in _scopeLabels.indexed) ...[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _scope = i;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: _scope == i
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: _scope == i
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary)),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
              ]),
            ),
          ),
          Expanded(child: _results()),
        ]),
      ),
    );
  }

  Widget _results() {
    if (!_searched) return _historyView();
    final types = _scopeTypes[_scope];
    return PagedScroll(
      key: ValueKey<String>('search|$_q|$types'),
      loader: (cursor) => cursor == null
          ? KodikApi.instance.search(query: _q, types: types, limit: 30)
          : KodikApi.instance.nextPage(cursor),
      itemBuilder: (context, title, _) =>
          ReleaseListItem.kodik(title, onTap: () => openTitle(context, title)),
      emptyText: 'По запросу «$_q» ничего не найдено',
    );
  }

  /// История запросов (эталон: скриншот 08).
  Widget _historyView() {
    if (_history.isEmpty) return const SizedBox.shrink();
    return ListView(shrinkWrap: true, children: [
      if (_history.length > 1)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed: _clearHistory,
              child: const Text('Очистить историю',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textTertiary))),
        ),
      for (final q in _history)
        ListTile(
          leading: const Icon(Icons.history, color: AppColors.textTertiary),
          title: Text(q,
              style: const TextStyle(
                  fontSize: 15, color: AppColors.textSecondary)),
          onTap: () => _useHistory(q),
        ),
    ]);
  }
}

/// Результаты применённого фильтра — открывается из Фильтра и «Моей вкладки».
class FilteredResultsScreen extends StatefulWidget {
  const FilteredResultsScreen({super.key, required this.filter});

  final CatalogFilter filter;

  @override
  State<FilteredResultsScreen> createState() => _FilteredResultsScreenState();
}

class _FilteredResultsScreenState extends State<FilteredResultsScreen> {
  Set<String> _watched = const <String>{};

  @override
  void initState() {
    super.initState();
    _loadWatched();
  }

  Future<void> _loadWatched() async {
    final ids = await Library.watchedTitleIds();
    if (mounted) setState(() => _watched = ids);
  }

  @override
  Widget build(BuildContext context) {
    final filter = widget.filter;
    final needsClientFilter = filter.minRating != null || filter.hideWatched;
    return PageScaffold(
      title: 'Подборка',
      body: PagedScroll(
        key: ValueKey<String>(filter.signature),
        loader: (cursor) => KodikApi.instance.fetch(filter, cursor: cursor),
        accept: needsClientFilter
            ? (title) => filter.accepts(title, watched: _watched)
            : null,
        itemBuilder: (context, title, _) => ReleaseListItem.kodik(title,
            onTap: () => openTitle(context, title)),
        emptyText: 'Ничего не найдено',
      ),
    );
  }
}
