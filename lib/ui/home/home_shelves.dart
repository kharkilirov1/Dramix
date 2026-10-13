import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Finite shelves have independent loading/error states; full results remain
/// available through the existing cursor-paginated catalog screen.
class CatalogShelf extends StatefulWidget {
  final String heading;
  final Future<List<KodikTitle>> Function() loader;
  final VoidCallback onSeeAll;

  const CatalogShelf({
    super.key,
    required this.heading,
    required this.loader,
    required this.onSeeAll,
  });

  @override
  State<CatalogShelf> createState() => _CatalogShelfState();
}

class _CatalogShelfState extends State<CatalogShelf> {
  List<KodikTitle> _items = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await widget.loader();
      for (final title in items) {
        await Library.registerTitle(title.ref);
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ShelfHeading(title: widget.heading, onSeeAll: widget.onSeeAll),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_failed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Не удалось загрузить подборку'),
            TextButton(onPressed: _load, child: const Text('Повторить')),
          ]),
        )
      else if (_items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Text('Здесь пока пусто',
              style: TextStyle(color: AppColors.textTertiary)),
        )
      else
        _PosterShelf(
          count: _items.length,
          builder: (context, i, width) => _PosterCard(
            title: _items[i].titleRu,
            image: _items[i].poster,
            subtitle: _items[i].subtitle,
            width: width,
            onTap: () => openTitle(context, _items[i]),
          ),
        ),
      const SizedBox(height: 16),
    ]);
  }
}

class ContinueWatchingShelf extends StatefulWidget {
  final Future<List<WatchEntry>> Function()? loader;

  const ContinueWatchingShelf({super.key, this.loader});

  @override
  State<ContinueWatchingShelf> createState() => _ContinueWatchingShelfState();
}

class _ContinueWatchingShelfState extends State<ContinueWatchingShelf> {
  List<WatchEntry> _entries = const [];
  bool _loading = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    Library.revision.addListener(_onChanged);
    _load();
  }

  void _onChanged() => _load();

  @override
  void dispose() {
    Library.revision.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final entries = await (widget.loader?.call() ??
          Library.continueWatching());
      if (!mounted || request != _request) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || (!_failed && _entries.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _ShelfHeading(title: 'Продолжить просмотр'),
      if (_failed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextButton(
            onPressed: _load,
            child: const Text('Не удалось прочитать историю. Повторить'),
          ),
        )
      else
        _PosterShelf(
          count: _entries.length,
          builder: (context, i, width) {
            final entry = _entries[i];
            final label = [
              if (entry.season != null) 'Сезон ${entry.season}',
              if (entry.episode != null) 'Серия ${entry.episode}',
            ].join(' · ');
            return _PosterCard(
              title: entry.title.title,
              image: entry.title.poster,
              subtitle: label,
              width: width,
              onTap: () => openSavedTitle(context, entry.title),
            );
          },
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Text('Откройте карточку, чтобы продолжить просмотр.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      ),
    ]);
  }
}

class _ShelfHeading extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _ShelfHeading({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('Все')),
      ]),
    );
  }
}

class _PosterShelf extends StatelessWidget {
  final int count;
  final Widget Function(BuildContext, int, double) builder;

  const _PosterShelf({required this.count, required this.builder});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth / 2.4).clamp(116.0, 180.0).toDouble();
      return SizedBox(
        height: width * 1.45 + 104 * scale,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: count,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => builder(context, i, width),
        ),
      );
    });
  }
}

class _PosterCard extends StatelessWidget {
  final String title;
  final String? image;
  final String subtitle;
  final double width;
  final VoidCallback onTap;

  const _PosterCard({
    required this.title,
    required this.image,
    required this.subtitle,
    required this.width,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Poster(url: image, width: width, height: width * 1.45, radius: 12),
          const SizedBox(height: 8),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}
