import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Finite shelves keep independent failures and routes to the full catalog.
class CatalogShelf extends StatefulWidget {
  final String heading;
  final String? subtitle;
  final bool featured;
  final Future<List<KodikTitle>> Function() loader;
  final VoidCallback onSeeAll;

  const CatalogShelf({
    super.key,
    required this.heading,
    this.subtitle,
    this.featured = false,
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
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await widget.loader();
      for (final title in items) {
        try {
          await Library.registerTitle(title.ref);
        } catch (_) {
          // A storage failure must not hide an otherwise available catalog.
        }
      }
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _loading = false;
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
    final visible = widget.featured && _items.isNotEmpty
        ? _items.skip(1).toList()
        : _items;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ShelfHeading(
        title: widget.heading,
        subtitle: widget.subtitle,
        onSeeAll: widget.onSeeAll,
      ),
      if (_loading)
        const _ShelfLoading()
      else if (_failed)
        _ShelfMessage(
          icon: Icons.wifi_off_rounded,
          title: 'Не удалось загрузить подборку',
          detail: 'Другие подборки и ваша история остаются доступны.',
          onRetry: _load,
        )
      else if (_items.isEmpty)
        const _ShelfMessage(
          icon: Icons.video_library_outlined,
          title: 'Здесь пока пусто',
          detail: 'В источнике нет подходящих тайтлов. Посмотрите весь каталог.',
        )
      else ...[
        if (widget.featured)
          _FeaturedTitle(
            title: _items.first,
            onOpen: () => openTitle(context, _items.first),
          ),
        if (visible.isNotEmpty)
          _PosterShelf(
            count: visible.length,
            builder: (context, i, width) {
              final title = visible[i];
              final rating = title.grade;
              final source = title.material?.ratingSource;
              final subtitle = [
                title.subtitle,
                if (rating != null && source != null)
                  '$source ${rating.toStringAsFixed(1)}',
              ].where((s) => s.isNotEmpty).join(' · ');
              return _PosterCard(
                title: title.titleRu,
                image: title.poster,
                subtitle: subtitle,
                width: width,
                onTap: () => openTitle(context, title),
              );
            },
          ),
      ],
      const SizedBox(height: 20),
    ]);
  }
}

/// Local checkpoints are prominent, without inventing a duration or percentage.
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
    if (_failed && _entries.isEmpty) setState(() => _loading = true);
    try {
      final entries =
          await (widget.loader?.call() ?? Library.continueWatching());
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
    if (_loading) {
      return Semantics(
        liveRegion: true,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Text('Загружаем историю…',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    if (!_failed && _entries.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _ShelfHeading(
        title: 'Продолжить просмотр',
        subtitle: 'Сохранённые серии из вашей истории',
      ),
      if (_failed)
        _ShelfMessage(
          icon: Icons.history_rounded,
          title: 'Не удалось прочитать историю',
          detail: 'Попробуйте ещё раз. Каталог доступен без входа.',
          onRetry: _load,
        )
      else
        LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final width =
              (constraints.maxWidth * 0.86).clamp(250.0, 380.0).toDouble();
          return SizedBox(
            height: math.max(148.0, 132 * scale),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _ContinueCard(
                entry: _entries[i],
                width: width,
                onOpen: () => openSavedTitle(context, _entries[i].title),
              ),
            ),
          );
        }),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Text('Откройте карточку, чтобы продолжить просмотр.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
    ]);
  }
}

class _ShelfHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;

  const _ShelfHeading({required this.title, this.subtitle, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w700)),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textSecondary)),
            ],
          ]),
        ),
        if (onSeeAll != null)
          Tooltip(
            message: 'Вся подборка: $title',
            child: TextButton(onPressed: onSeeAll, child: const Text('Все')),
          ),
      ]),
    );
  }
}

class _ShelfMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  const _ShelfMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 24, color: AppColors.textSecondary),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(detail,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Повторить'),
            ),
          ],
        ]),
      ),
    );
  }
}

class _ShelfLoading extends StatelessWidget {
  const _ShelfLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Загружаем подборку',
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 236,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, __) => SizedBox(
              width: 144,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 190,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(height: 10, width: 116, color: AppColors.surface),
                  const SizedBox(height: 6),
                  Container(height: 8, width: 72, color: AppColors.surface),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedTitle extends StatelessWidget {
  final KodikTitle title;
  final VoidCallback onOpen;

  const _FeaturedTitle({required this.title, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final description = stripHtml(title.description ?? '').trim();
    final metadata = [
      if (title.year != null) '${title.year}',
      title.material?.countryLabel ?? '',
      if (title.genreList.isNotEmpty) title.genreList.take(2).join(', '),
    ].where((s) => s.isNotEmpty).join(' · ');
    final rating = title.grade;
    final source = title.material?.ratingSource;
    final details = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.titleRu,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(metadata,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
        ],
        if (rating != null && source != null) ...[
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, size: 18, color: AppColors.statHoldOn),
            const SizedBox(width: 5),
            Flexible(
              child: Text('$source ${rating.toStringAsFixed(1)}',
                  style: const TextStyle(fontSize: 13)),
            ),
          ]),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.info_outline_rounded),
          label: const Text('Подробнее'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.light,
            foregroundColor: Colors.black,
            minimumSize: const Size(0, 48),
          ),
        ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= 680 &&
              MediaQuery.textScalerOf(context).scale(1) < 1.5;
          final image = AspectRatio(
            aspectRatio: wide ? 1.4 : 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              RemoteImage(url: title.image, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
            ]),
          );
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: constraints.maxWidth * 0.42, child: image),
              Expanded(child: details),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [image, details]);
        }),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final WatchEntry entry;
  final double width;
  final VoidCallback onOpen;

  const _ContinueCard({
    required this.entry,
    required this.width,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final label = [
      if (entry.season != null) 'Сезон ${entry.season}',
      if (entry.episode != null) 'Серия ${entry.episode}',
    ].join(' · ');
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '${entry.title.title}. $label. Открыть карточку для продолжения.',
        onTap: onOpen,
        child: ExcludeSemantics(
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              focusColor: AppColors.accent,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Stack(alignment: Alignment.center, children: [
                    Poster(url: entry.title.poster, width: 76, height: 112,
                        radius: 10),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 25),
                    ),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title.title, maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        if (label.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(label, maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5,
                                  color: AppColors.textSecondary)),
                        ],
                        const SizedBox(height: 8),
                        const Text('Открыть карточку', maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
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
      final width =
          (constraints.maxWidth / 2.2).clamp(136.0, 188.0).toDouble();
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
    required this.title, required this.image, required this.subtitle,
    required this.width, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        label: '$title. $subtitle. Открыть карточку.',
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              focusColor: AppColors.accent,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Poster(url: image, width: width, height: width * 1.45,
                      radius: 12),
                  const SizedBox(height: 10),
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12,
                          color: AppColors.textSecondary, height: 1.4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
