import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../filter/filter_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../search/search_screen.dart';
import '../widgets.dart';

/// Обзор: баннеры, плитки действий, рекомендации и лента онгоингов.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<KodikTitle> _banners = const <KodikTitle>[];

  @override
  void initState() {
    super.initState();
    _loadBanners();
  }

  Future<void> _loadBanners() async {
    try {
      final page = await KodikApi.instance.browseFiltered(
        CatalogFilter(sort: CatalogSort.rating, types: KodikCatalog.all),
        limit: 6,
      );
      final titles = KodikApi.dedupe(page.results)
          .where((t) => (t.poster ?? '').trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _banners = titles);
    } catch (_) {
      // Баннеры — необязательный блок: при ошибке просто не показываем его.
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
    try {
      final title = await KodikApi.instance.randomTitle();
      if (!mounted || title == null) return;
      await openTitle(context, title);
    } catch (_) {
      // Случайный тайтл — необязательное действие: ошибку молча пропускаем.
    }
  }

  Widget _tileRow(List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: tiles[i]),
        ],
      ]),
    );
  }

  Widget _bannerCard(BuildContext context, KodikTitle title) {
    final country = title.material?.countryLabel ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        width: 310,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
          if (_banners.isNotEmpty)
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _banners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _bannerCard(context, _banners[i]),
              ),
            ),
          const SizedBox(height: 14),

          // Плитки действий в два столбца.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              _tileRow(<Widget>[
                BigPillButton(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Популярное',
                  onTap: () => Navigator.pushNamed(context, Routes.popular),
                ),
                BigPillButton(
                  icon: Icons.calendar_today_outlined,
                  label: 'Расписание',
                  onTap: () => Navigator.pushNamed(context, Routes.schedule),
                ),
              ]),
              _tileRow(<Widget>[
                BigPillButton(
                  icon: Icons.reorder,
                  label: 'Коллекции',
                  onTap: () => Navigator.pushNamed(context, Routes.collections),
                ),
                BigPillButton(
                  icon: Icons.tune,
                  label: 'Фильтр',
                  onTap: _openFilter,
                ),
              ]),
              _tileRow(<Widget>[
                BigPillButton(
                  icon: Icons.shuffle,
                  label: 'Рандом',
                  onTap: _openRandom,
                ),
                const SizedBox(),
              ]),
            ]),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 26, 16, 4),
            child: Text('Рекомендации',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('На основе ваших оценок',
                style:
                    TextStyle(fontSize: 13.5, color: AppColors.textTertiary)),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Продолжайте смотреть и оценивать дорамы.\n'
              'Чем больше вы смотрите, тем точнее будут подборки.',
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.5),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 26, 16, 8),
            child: Text('Сейчас выходят',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 420,
            child: PagedScroll(
              key: const ValueKey('discover-ongoing'),
              loader: (cursor) => KodikApi.instance.fetch(
                CatalogFilter(
                    allStatus: AiringStatus.ongoing.value,
                    types: KodikCatalog.all),
                cursor: cursor,
              ),
              itemBuilder: (context, title, _) => ReleaseListItem.kodik(
                title,
                onTap: () => openTitle(context, title),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
