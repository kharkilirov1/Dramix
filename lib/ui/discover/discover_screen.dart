import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../filter/filter_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../search/search_screen.dart';
import '../widgets.dart';
import '../home/home_shelves.dart';

/// Обзор: подборки каталога, навигация и сериалы со статусом ongoing.
class DiscoverScreen extends StatefulWidget {
  final Future<List<KodikTitle>> Function()? bannersLoader;
  final Future<List<KodikTitle>> Function()? ongoingLoader;
  final Future<KodikTitle?> Function()? randomLoader;

  const DiscoverScreen({super.key, this.bannersLoader,
    this.ongoingLoader, this.randomLoader});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<KodikTitle> _banners = const <KodikTitle>[];
  bool _bannerLoading = true;
  bool _bannerFailed = false;
  bool _randomBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    setState(() {
      _bannerLoading = true;
      _bannerFailed = false;
    });
    try {
      final titles = widget.bannersLoader == null
          ? (await KodikApi.instance.browseFiltered(
              CatalogFilter(sort: CatalogSort.rating, types: KodikCatalog.dramas),
              limit: 6,
            )).results
          : await widget.bannersLoader!();
      if (!mounted) return;
      setState(() {
        _banners = KodikApi.dedupe(titles)
            .where((title) => (title.poster ?? '').trim().isNotEmpty).toList();
        _bannerLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bannerLoading = false;
        _bannerFailed = true;
      });
    }
  }

  Future<void> _openFilter() async {
    final f = await Navigator.push<CatalogFilter>(
      context,
      MaterialPageRoute(builder: (_) => const FilterScreen()),
    );
    if (!mounted || f == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FilteredResultsScreen(filter: f)),
    );
  }

  Future<void> _openRandom() async {
    if (_randomBusy) return;
    setState(() => _randomBusy = true);
    try {
      final title = await (widget.randomLoader?.call() ??
          KodikApi.instance.randomTitle());
      if (!mounted) return;
      if (title == null) {
        showMessage(context, 'Не удалось найти подходящий тайтл. Попробуйте ещё раз.');
      } else {
        await openTitle(context, title);
      }
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Не удалось выбрать тайтл. Попробуйте ещё раз.');
      }
    } finally {
      if (mounted) setState(() => _randomBusy = false);
    }
  }

  Widget _tileRow(List<Widget> tiles) {
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(16) > 22;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: stacked || tiles.length == 1
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  tiles[i],
                ],
              ])
            : Row(children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: tiles[i]),
                ],
              ]),
      );
    });
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(icon, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text(label,
                    style: const TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w500))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bannerCard(BuildContext context, KodikTitle title, double width) {
    final country = title.material?.countryLabel ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: width,
        child: InkWell(
          onTap: () => openTitle(context, title),
          child: Stack(fit: StackFit.expand, children: [
            RemoteImage(url: title.poster, fit: BoxFit.cover),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.75),
                    ],
                  ),
                ),
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
                  Text(title.titleRu,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (country.isNotEmpty)
                    Text(country,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          TopBar(
            searchHint: 'Поиск дорам',
            onSearch: () => Navigator.pushNamed(context, Routes.search),
          ),

          // Баннеры — самые рейтинговые тайтлы каталога.
          if (_bannerLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bannerFailed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Не удалось загрузить тайтлы с высоким рейтингом'),
                TextButton(onPressed: _loadBanners, child: const Text('Повторить')),
              ]),
            )
          else if (_banners.isNotEmpty)
            SizedBox(
              height: 150 + 40 * MediaQuery.textScalerOf(context).scale(1),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _banners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _bannerCard(context, _banners[i],
                    (MediaQuery.sizeOf(context).width - 48).clamp(220.0, 360.0).toDouble()),
              ),
            ),
          const SizedBox(height: 14),

          // Плитки действий в два столбца.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _tileRow(<Widget>[
                _actionTile(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Высокий рейтинг',
                  onTap: () => Navigator.pushNamed(context, Routes.popular),
                ),
                _actionTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Обновления по дням',
                  onTap: () => Navigator.pushNamed(context, Routes.schedule),
                ),
              ]),
              _tileRow(<Widget>[
                _actionTile(
                  icon: Icons.reorder,
                  label: 'Коллекции',
                  onTap: () => Navigator.pushNamed(context, Routes.collections),
                ),
                _actionTile(
                  icon: Icons.tune,
                  label: 'Фильтр',
                  onTap: _openFilter,
                ),
              ]),
              _tileRow(<Widget>[
                _actionTile(
                  icon: Icons.shuffle,
                  label: _randomBusy ? 'Выбираем тайтл…' : 'Случайный тайтл',
                  onTap: _randomBusy ? null : _openRandom,
                ),
              ]),
            ]),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 8),
            child: Text('Подборки по странам и жанрам доступны в коллекциях.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          ),

          CatalogShelf(
            heading: 'Сейчас выходят',
            loader: widget.ongoingLoader ?? () async {
              final page = await KodikApi.instance.browseFiltered(
                CatalogFilter(
                    allStatus: AiringStatus.ongoing.value,
                    types: KodikCatalog.dramas),
                limit: 18,
              );
              return KodikApi.dedupe(page.results);
            },
            onSeeAll: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FilteredResultsScreen(
                  filter: CatalogFilter(
                      allStatus: AiringStatus.ongoing.value,
                      types: KodikCatalog.dramas),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
