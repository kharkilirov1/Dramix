import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Популярное: табы Онгоинги / Завершенные / Фильмы / Мультфильмы
/// и нумерованный список по оценке.
class PopularScreen extends StatefulWidget {
  const PopularScreen({super.key});

  @override
  State<PopularScreen> createState() => _PopularScreenState();
}

class _PopularScreenState extends State<PopularScreen> {
  int _tab = 0;

  CatalogFilter _filterFor(int tab) {
    switch (tab) {
      case 1:
        return CatalogFilter(sort: CatalogSort.rating)
          ..allStatus = AiringStatus.released.value;
      case 2:
        return CatalogFilter(types: KodikCatalog.movies, sort: CatalogSort.rating);
      case 3:
        return CatalogFilter(
            types: KodikCatalog.cartoons, sort: CatalogSort.rating);
      case 0:
      default:
        return CatalogFilter(sort: CatalogSort.rating)
          ..allStatus = AiringStatus.ongoing.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filterFor(_tab);
    return PageScaffold(
      title: 'Популярное',
      body: Column(
        children: [
          UnderlineTabs(
            tabs: const ['Онгоинги', 'Завершенные', 'Фильмы', 'Мультфильмы'],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          Expanded(
            child: PagedScroll(
              key: ValueKey(filter.signature),
              loader: (cursor) => KodikApi.instance.fetch(filter, cursor: cursor),
              itemBuilder: (context, title, index) => ReleaseListItem.kodik(
                title,
                rank: index + 1,
                onTap: () => openTitle(context, title),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
