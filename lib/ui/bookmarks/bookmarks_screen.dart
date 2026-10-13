import 'package:flutter/material.dart';

import '../../core/collections.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../collections/collections_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../widgets.dart';

/// Закладки: contextual tabs + «ВСЕГО» + sort pill + local list.
///
/// Kodik has no accounts, so «Коллекции» renders the curated sets and every
/// other tab reads the offline [Library].
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  int _tab = 2; // Избранное active, like the reference app

  /// Tabs 3–7 follow [WatchStatus] so the labels never drift from the enum.
  static final List<String> _tabs = <String>[
    'Коллекции',
    'История',
    'Избранное',
    for (final s in WatchStatus.values) s.title,
  ];

  List<SavedTitleRef> _items = const <SavedTitleRef>[];
  bool _loading = true;
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
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) _load();
  }

  /// Reloads the selected tab and ignores reads superseded by a newer request.
  Future<void> _load() async {
    final token = ++_request;
    final tab = _tab;
    // «Коллекции» is a static curated list, there is nothing to read locally.
    if (tab == 0) {
      setState(() {
        _items = const <SavedTitleRef>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<SavedTitleRef> items;
      switch (tab) {
        case 1:
          items = (await Library.history()).map((e) => e.title).toList();
        case 2:
          items = await Library.favorites();
        default:
          items = await Library.list(WatchStatus.values[tab - 3]);
      }
      if (!mounted || token != _request) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _request) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        TopBar(
          searchHint: 'Поиск в «${_tabs[_tab]}»',
          onSearch: () => Navigator.pushNamed(context, Routes.search),
        ),
        UnderlineTabs(
          tabs: _tabs,
          selected: _tab,
          onChanged: (i) {
            if (i == _tab) return;
            setState(() => _tab = i);
            _load();
          },
          separator: 22,
        ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey<int>(_tab),
            child: Column(children: [
              _header(),
              Expanded(child: _body()),
            ]),
          ),
        ),
      ]),
    );
  }

  /// Хедер «ВСЕГО · По добавл. ▼ · Шаффл» из эталона.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(children: [
        const Text('ВСЕГО',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textTertiary,
                letterSpacing: 0.5)),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.reorder, size: 15, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Text('По добавл.',
                style:
                    TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down,
                size: 17, color: AppColors.textSecondary),
          ]),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.shuffle,
              size: 20, color: AppColors.textSecondary),
          onPressed: () {},
        ),
      ]),
    );
  }

  Widget _body() {
    if (_tab == 0) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: Curated.all.length,
        itemBuilder: (context, i) {
          final c = Curated.all[i];
          return CollectionCard(
            collection: c,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => CollectionDetailScreen(collection: c)),
            ),
          );
        },
      );
    }
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.textSecondary));
    }
    if (_error != null) {
      return ErrorCentered(message: _error!, onRetry: _load);
    }
    final emptyText = switch (_tab) {
      1 => 'История пуста',
      2 => 'В избранном пока пусто',
      _ => 'В этом списке пока пусто',
    };
    return SavedList(
      items: _items,
      emptyText: emptyText,
      onTap: (context, t) => openSavedTitle(context, t),
    );
  }
}
