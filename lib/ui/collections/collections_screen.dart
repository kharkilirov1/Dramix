import 'package:flutter/material.dart';

import '../../core/collections.dart';
import '../../core/kodik_api.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Кэш обложек и счётчиков коллекций: записи не перезапрашиваются при rebuild.
typedef _CollectionPreview = ({String? cover, int? count});

/// Коллекции: кураторские подборки Kodik.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  /// Cached *Future* (not result) so `FutureBuilder` sees a stable identity and
  /// covers do not flash back to the gradient on every rebuild.
  final Map<String, Future<_CollectionPreview>> _previews =
      <String, Future<_CollectionPreview>>{};

  Future<_CollectionPreview> _preview(CuratedCollection c) =>
      _previews.putIfAbsent(c.id, () => _fetch(c));

  Future<_CollectionPreview> _fetch(CuratedCollection c) async {
    try {
      final page = await KodikApi.instance.browseFiltered(c.filter, limit: 1);
      final results = page.results;
      return (
        cover: results.isEmpty ? null : results.first.poster,
        count: page.total,
      );
    } catch (_) {
      return (cover: null, count: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Коллекции',
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        itemCount: Curated.all.length,
        itemBuilder: (context, index) {
          final c = Curated.all[index];
          return FutureBuilder<_CollectionPreview>(
            future: _preview(c),
            builder: (context, snapshot) {
              final data = snapshot.data;
              return CollectionCard(
                collection: c,
                image: data?.cover,
                count: data?.count,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CollectionDetailScreen(collection: c)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Наполнение коллекции.
class CollectionDetailScreen extends StatelessWidget {
  final CuratedCollection collection;

  const CollectionDetailScreen({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: collection.title,
      body: PagedScroll(
        key: ValueKey<String>(collection.signature),
        loader: (cursor) =>
            KodikApi.instance.fetch(collection.filter, cursor: cursor),
        itemBuilder: (context, title, _) => ReleaseListItem.kodik(
          title,
          onTap: () => openTitle(context, title),
        ),
        emptyText: 'В этой подборке пока пусто',
      ),
    );
  }
}
