import 'package:flutter/material.dart';

import '../../core/collections.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../collections/collections_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../widgets.dart';
import 'library_row.dart';

enum _LibraryOrder { saved, title }

/// Guest library stays local; optional cloud uploads do not replace these lists.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  int _tab = 2;
  static final List<String> _tabs = <String>[
    'Коллекции', 'История', 'Избранное',
    for (final status in WatchStatus.values) status.title,
  ];
  final _search = TextEditingController();
  String _query = '';
  _LibraryOrder _order = _LibraryOrder.saved;
  List<SavedTitleRef> _items = const [];
  List<WatchEntry> _history = const [];
  bool _loading = true;
  bool _clearing = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    Library.revision.addListener(_onLibraryChanged);
    _load();
  }

  @override
  void dispose() {
    Library.revision.removeListener(_onLibraryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) _load();
  }

  bool _matches(String title) => title.toLowerCase().contains(_query.trim().toLowerCase());

  List<SavedTitleRef> get _visibleItems {
    final items = _items.where((item) => _matches(item.title)).toList();
    if (_order == _LibraryOrder.title) {
      items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return items;
  }

  List<WatchEntry> get _visibleHistory {
    final entries = _history.where((entry) => _matches(entry.title.title)).toList();
    if (_order == _LibraryOrder.title) {
      entries.sort((a, b) => a.title.title.toLowerCase().compareTo(b.title.title.toLowerCase()));
    } else {
      entries.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    }
    return entries;
  }

  List<CuratedCollection> get _visibleCollections {
    final entries = Curated.all.where((entry) => _matches(entry.title)).toList();
    if (_order == _LibraryOrder.title) {
      entries.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return entries;
  }

  Future<void> _load() async {
    final request = ++_request;
    final tab = _tab;
    if (tab == 0) {
      setState(() { _loading = false; _error = null; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      List<WatchEntry> history = const [];
      final List<SavedTitleRef> items;
      if (tab == 1) {
        history = await Library.history();
        items = history.map((entry) => entry.title).toList();
      } else if (tab == 2) {
        items = await Library.favorites();
      } else {
        items = await Library.list(WatchStatus.values[tab - 3]);
      }
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _history = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = 'Не удалось открыть библиотеку устройства';
        _loading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing || _history.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Удалить сохранённые позиции всех серий на этом устройстве? '
            'Избранное и списки останутся. Облачные данные не изменятся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Очистить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await Library.clearHistory();
      if (mounted) showMessage(context, 'История устройства очищена');
    } catch (_) {
      if (mounted) showMessage(context, 'Не удалось очистить историю');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Column(children: [
      TopBar(searchHint: 'Поиск дорам', onSearch: () => Navigator.pushNamed(context, Routes.search)),
      UnderlineTabs(
        tabs: _tabs, selected: _tab, separator: 22,
        onChanged: (tab) {
          if (_tab == tab) return;
          _search.clear();
          setState(() { _tab = tab; _query = ''; });
          _load();
        },
      ),
      Expanded(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(children: [
          _controls(),
          Expanded(child: KeyedSubtree(key: ValueKey<int>(_tab), child: _body())),
        ]),
      ))),
    ]),
  );

  Widget _controls() {
    final count = _tab == 0 ? _visibleCollections.length :
        _tab == 1 ? _visibleHistory.length : _visibleItems.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const ValueKey<String>('library-search'),
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: _tab == 0 ? 'Найти подборку' : 'Найти в этой вкладке',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty ? null : IconButton(
              tooltip: 'Сбросить поиск',
              icon: const Icon(Icons.close),
              onPressed: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_loading ? 'Загрузка…' : 'Записей: $count',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            SizedBox(width: 220, child: DropdownButton<_LibraryOrder>(
              isExpanded: true,
              key: const ValueKey<String>('library-sort'),
              value: _order,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(value: _LibraryOrder.saved,
                  child: Text(_tab == 1 ? 'Последние записи' : 'Порядок списка',
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                const DropdownMenuItem(value: _LibraryOrder.title, child: Text('По названию',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (order) { if (order != null) setState(() => _order = order); },
            )),
            if (_tab == 1)
              IconButton(
                tooltip: 'Очистить историю',
                onPressed: _loading || _clearing || _history.isEmpty ? null : _clearHistory,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        if (_tab != 0)
          const Text('На этом устройстве',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textSecondary));
    }
    if (_error != null) return ErrorCentered(message: _error!, onRetry: _load);
    if (_tab == 0) {
      final entries = _visibleCollections;
      if (entries.isEmpty) return _empty(filtered: true);
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: entries.length,
        itemBuilder: (context, index) => CollectionCard(
          collection: entries[index],
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => CollectionDetailScreen(collection: entries[index]))),
        ),
      );
    }
    final history = _visibleHistory;
    final items = _visibleItems;
    if ((_tab == 1 ? history.length : items.length) == 0) {
      return _empty(filtered: _query.trim().isNotEmpty);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _tab == 1 ? history.length : items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final checkpoint = _tab == 1 ? history[index] : null;
        final title = checkpoint?.title ?? items[index];
        return LibraryRow(
          key: ValueKey<String>('${title.id}:${checkpoint?.season}:${checkpoint?.episode}'),
          title: title, checkpoint: checkpoint,
          onOpen: () => openSavedTitle(context, title),
        );
      },
    );
  }

  Widget _empty({required bool filtered}) {
    final title = filtered ? 'Ничего не найдено' : switch (_tab) {
      1 => 'История пуста',
      2 => 'В избранном пока пусто',
      _ => 'В этом списке пока пусто',
    };
    final description = filtered
        ? 'Попробуйте другое название или сбросьте поиск.'
        : _tab == 1
          ? 'Сохранённые серии появятся здесь после подтверждённого просмотра.'
          : 'Добавьте дораму в избранное или список на её карточке.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        const Icon(Icons.video_library_outlined, size: 42, color: AppColors.textTertiary),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(description, textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        Center(child: TextButton.icon(
          onPressed: filtered ? () {
            _search.clear();
            setState(() => _query = '');
          } : () => Navigator.pushNamed(context, Routes.search),
          icon: Icon(filtered ? Icons.close : Icons.search),
          label: Text(filtered ? 'Сбросить поиск' : 'Найти дораму'),
        )),
      ],
    );
  }
}
