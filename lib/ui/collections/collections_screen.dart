import 'package:flutter/material.dart';

import '../../core/collections.dart';
import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Cached optional cover previews, independent of collection navigation.
typedef _CollectionPreview = ({String? cover, bool failed});

/// Collections are catalog filters, not community-created or personal lists.
String collectionDescription(CuratedCollection collection) {
  final criteria = <String>[
    collection.types == KodikCatalog.movies ? 'Фильмы' : 'Сериалы',
    ...collection.countries,
    ...collection.genres,
    if (collection.year != null) 'Год выпуска: ${collection.year}',
    if (collection.allStatus == AiringStatus.ongoing.value) 'Сейчас выходят',
    if (collection.allStatus == AiringStatus.released.value) 'Завершённые',
  ];
  return '${criteria.join(' · ')} · По рейтингу';
}

CuratedCollection _displayCollection(CuratedCollection collection) =>
    CuratedCollection(
      id: collection.id, title: collection.title,
      subtitle: collectionDescription(collection), types: collection.types,
      genres: collection.genres, countries: collection.countries,
      year: collection.year, allStatus: collection.allStatus,
    );
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
        failed: false,
      );
    } catch (_) {
      return (cover: null, failed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Коллекции',
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        itemCount: Curated.all.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text('Подборки по странам, жанрам и году выпуска. '
                  'Состав зависит от доступных записей каталога Kodik.',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          final c = Curated.all[index - 1];
          return FutureBuilder<_CollectionPreview>(
            future: _preview(c),
            builder: (context, snapshot) {
              final data = snapshot.data;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CollectionCard(
                collection: _displayCollection(c),
                image: data?.cover,
                // Provider total counts dubbing records, not unique works.
                // Keep discovery cards navigable without inventing a title count.
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CollectionDetailScreen(collection: c)),
                ),
              ),
              if (data?.failed == true)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextButton(
                    onPressed: () => setState(() => _previews.remove(c.id)),
                    child: const Text('Не удалось загрузить обложку. Повторить'),
                  ),
                ),
              ]);
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
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Text(collectionDescription(collection),
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
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
