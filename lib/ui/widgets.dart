import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/collections.dart';
import '../core/models.dart';
import '../core/theme.dart';

/// Removes HTML tags — some Kodik descriptions carry `<br>` and friends.
String stripHtml(String s) =>
    s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll('  ', ' ');

/// Network image with a two-stage load.
///
/// Tries the disk cache first ([CachedNetworkImage]), and if that fails falls
/// back to a plain network fetch. The fallback matters on locked-down Windows
/// installs where the cache directory is not writable: without it every poster
/// degrades to a grey box even though the network itself is fine.
class RemoteImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? radius;

  const RemoteImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final src = (url ?? '').trim();

    Widget surface() => Container(
          width: width,
          height: height,
          color: AppColors.surface,
          alignment: Alignment.center,
          child: const ExcludeSemantics(
            child: Icon(Icons.movie_outlined,
                size: 28, color: AppColors.textTertiary),
          ),
        );

    Widget content = src.isEmpty
        ? surface()
        : CachedNetworkImage(
            imageUrl: src,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => surface(),
            errorWidget: (_, failedUrl, __) => Image.network(
              failedUrl,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, __, ___) => surface(),
            ),
          );

    final r = radius;
    return r == null ? content : ClipRRect(borderRadius: r, child: content);
  }
}

/// Poster with rounded corners and a fade placeholder.
class Poster extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;

  const Poster({
    super.key,
    this.url,
    required this.width,
    required this.height,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) => RemoteImage(
        url: url,
        width: width,
        height: height,
        radius: BorderRadius.circular(radius),
      );
}

/// The list item used across Главная / Закладки / Популярное / Поиск.
///
/// Responsive poster row with optional rank, source-labelled rating and metadata.
class ReleaseListItem extends StatelessWidget {
  final String title;
  final String? image;
  final double? grade;
  final String? ratingSource;
  final String meta;
  final String? description;
  final int? rank;
  final VoidCallback? onTap;

  const ReleaseListItem({
    super.key,
    required this.title,
    this.image,
    this.grade,
    this.ratingSource,
    this.meta = '',
    this.description,
    this.rank,
    this.onTap,
  });

  /// Builds an item from a Kodik catalog entry.
  ReleaseListItem.kodik(KodikTitle t, {this.rank, this.onTap, super.key})
      : title = t.titleRu,
        image = t.image,
        grade = t.grade,
        ratingSource = t.material?.ratingSource,
        meta = [if (t.year != null) '${t.year}', t.episodesLabel]
            .where((part) => part.isNotEmpty).join(' · '),
        description = t.description;

  /// Builds an item from a locally stored snapshot.
  ReleaseListItem.saved(SavedTitleRef t, {this.onTap, super.key})
      : title = t.title,
        image = t.poster,
        grade = null,
        ratingSource = null,
        meta = t.subtitle,
        description = null,
        rank = null;

  @override
  Widget build(BuildContext context) {
    final desc = stripHtml(description ?? '').trim();
    final score = grade;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rank != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10, top: 2),
                  child: Text('$rank',
                      style: const TextStyle(
                          fontSize: 16, color: AppColors.textSecondary)),
                ),
              Poster(url: image, width: 78, height: 112, radius: 12),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3)),
                    if (meta.trim().isNotEmpty ||
                        (score != null && score > 0)) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (meta.trim().isNotEmpty)
                            Text(meta,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary)),
                          if (score != null && score > 0)
                            Text(
                              '${score.toStringAsFixed(1)} ★'
                              '${ratingSource == null ? '' : ' · $ratingSource'}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ],
                    if (desc.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(desc,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              height: 1.4)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal tabs row with the active underline.
class UnderlineTabs extends StatelessWidget {
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  final double separator;

  const UnderlineTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.separator = 24,
  });

  @override
  Widget build(BuildContext context) {
    final height = 32 + MediaQuery.textScalerOf(context).scale(16);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => SizedBox(width: separator),
        itemBuilder: (context, i) {
          final active = i == selected;
          return Semantics(
            selected: active,
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(i),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: active
                          ? AppColors.textPrimary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(tabs[i],
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? AppColors.textPrimary : AppColors.textSecondary)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Big rounded dark pill used in Обзор and elsewhere.
class BigPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  const BigPillButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 24, color: AppColors.textPrimary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

/// Light filled pill button (Воспроизвести / Применить / Войти).
class LightPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;

  const LightPillButton({
    super.key,
    required this.label,
    this.icon,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      liveRegion: loading,
      label: loading ? '$label, загрузка' : null,
      child: Material(
        color: enabled || loading ? AppColors.light : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(32),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.black54))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 22,
                            color: enabled ? Colors.black : AppColors.textSecondary),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: enabled
                                    ? Colors.black : AppColors.textSecondary)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class ErrorCentered extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorCentered({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 32, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.4)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Повторить'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard page scaffold: back arrow + title + optional actions.
class PageScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget body;

  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SizedBox(
            height: 34 + MediaQuery.textScalerOf(context).scale(21),
            child: Row(children: [
              const SizedBox(width: 8),
              IconButton(
                  tooltip: 'Назад',
                  icon: const Icon(Icons.arrow_back,
                      color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w700)),
              ),
              ...actions,
              const SizedBox(width: 8),
            ]),
          ),
          const Divider(height: 1, color: AppColors.outline),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

/// Cursor-paginated list of Kodik titles.
///
/// Kodik paginates with an opaque `next_page` URL rather than page numbers, and
/// repeats a title once per dubbing studio — so loaded pages are deduped by
/// [KodikTitle.dedupeKey].
class PagedScroll extends StatefulWidget {
  final Future<KodikPage> Function(String? cursor) loader;
  final Widget Function(BuildContext context, KodikTitle title, int index)
      itemBuilder;
  final Widget? header;
  final String emptyText;
  final bool dedupe;

  /// Client-side predicate for the parts of a filter Kodik cannot express.
  final bool Function(KodikTitle title)? accept;
  final EdgeInsets padding;

  const PagedScroll({
    super.key,
    required this.loader,
    required this.itemBuilder,
    this.header,
    this.emptyText = 'Здесь пока пусто',
    this.dedupe = true,
    this.accept,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<PagedScroll> createState() => _PagedScrollState();
}

class _PagedScrollState extends State<PagedScroll> {
  final List<KodikTitle> _items = <KodikTitle>[];
  final Set<String> _seen = <String>{};
  static const int _maxAutoLoads = 6;
  int _autoLoads = 0;
  String? _cursor;
  bool _loading = false;
  bool _canMore = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_canMore) return;
    final token = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.loader(_cursor);
      if (!mounted || token != _request) return;
      final fresh = <KodikTitle>[];
      for (final item in page.results) {
        if (widget.accept != null && !widget.accept!(item)) continue;
        if (widget.dedupe && !_seen.add(item.dedupeKey)) continue;
        fresh.add(item);
      }
      setState(() {
        _items.addAll(fresh);
        _cursor = page.nextPage;
        if (!page.hasMore || page.results.isEmpty) _canMore = false;
        _loading = false;
        _error = null;
      });
      // A client-side filter can empty a page entirely; keep pulling while
      // there is more catalog, otherwise the list would look broken.
      if (_items.isEmpty && _canMore && _autoLoads < _maxAutoLoads && mounted) {
        _autoLoads++;
        unawaited(_load());
      }
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
    if (_items.isEmpty && _loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.textSecondary));
    }
    if (_items.isEmpty && _error != null) {
      return ErrorCentered(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty && _canMore) {
      return Center(
        child: TextButton(
          onPressed: () {
            _autoLoads = 0;
            _load();
          },
          child: const Text('Загрузить ещё'),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(widget.emptyText,
            style: const TextStyle(color: AppColors.textTertiary)),
      );
    }

    final headerCount = widget.header != null ? 1 : 0;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_error == null &&
            n.metrics.pixels > n.metrics.maxScrollExtent - 500) {
          _load();
        }
        return false;
      },
      child: ListView.builder(
        padding: widget.padding,
        itemCount: _items.length + headerCount + (_canMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (headerCount == 1) {
            if (index == 0) return widget.header!;
            index -= 1;
          }
          if (index >= _items.length) {
            if (_error != null) {
              return ErrorCentered(message: _error!, onRetry: _load);
            }
            if (!_loading) {
              return Center(
                child: TextButton(
                  onPressed: _load,
                  child: const Text('Загрузить ещё'),
                ),
              );
            }
            return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.textSecondary)));
          }
          return widget.itemBuilder(context, _items[index], index);
        },
      ),
    );
  }
}

/// Vertical list of locally stored titles (history, favourites, watch lists).
class SavedList extends StatelessWidget {
  final List<SavedTitleRef> items;
  final void Function(BuildContext context, SavedTitleRef title) onTap;
  final String emptyText;
  final Widget? header;

  const SavedList({
    super.key,
    required this.items,
    required this.onTap,
    this.emptyText = 'Здесь пока пусто',
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textTertiary)),
        ),
      );
    }
    final headerCount = header != null ? 1 : 0;
    return ListView.builder(
      itemCount: items.length + headerCount,
      itemBuilder: (context, index) {
        if (headerCount == 1) {
          if (index == 0) return header!;
          index -= 1;
        }
        final item = items[index];
        return ReleaseListItem.saved(item, onTap: () => onTap(context, item));
      },
    );
  }
}

/// Large banner card used for collections.
class CollectionCard extends StatelessWidget {
  final CuratedCollection collection;
  final String? image;
  final int? count;
  final VoidCallback? onTap;

  const CollectionCard({
    super.key,
    required this.collection,
    this.image,
    this.count,
    this.onTap,
  });

  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFF3A2E52), Color(0xFF6B4E8C)],
    <Color>[Color(0xFF23384A), Color(0xFF3E6E8E)],
    <Color>[Color(0xFF4A2E2E), Color(0xFF8C4E4E)],
    <Color>[Color(0xFF2E4A38), Color(0xFF4E8C62)],
    <Color>[Color(0xFF463A22), Color(0xFF8C6C3E)],
  ];

  @override
  Widget build(BuildContext context) {
    final seed = collection.id.codeUnits.fold<int>(0, (a, b) => a + b);
    final gradient = _gradients[seed % _gradients.length];
    final src = (image ?? '').trim();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        height: 190,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: src.isEmpty
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: src,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradient),
                      ),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.72)
                    ]),
              ),
            ),
          ),
          if (count != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Text('$count',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  const Icon(Icons.movie_outlined,
                      size: 15, color: Colors.white),
                ]),
              ),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(collection.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(collection.subtitle,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Snackbar helper used across screens.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
