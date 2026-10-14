import 'models.dart';

/// A curated, editor-made collection.
///
/// Kodik has no user collections, so these are built from its own filters and
/// rendered with the reference client's banner card.
class CuratedCollection {
  final String id;
  final String title;
  final String subtitle;
  final String types;
  final Set<String> genres;
  final Set<String> countries;
  final int? year;
  final String? allStatus;

  const CuratedCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    this.types = KodikCatalog.dramas,
    this.genres = const <String>{},
    this.countries = const <String>{},
    this.year,
    this.allStatus,
  });

  CatalogFilter get filter => CatalogFilter(
        types: types,
        genres: <String>{...genres},
        countries: <String>{...countries},
        year: year,
        allStatus: allStatus,
        sort: CatalogSort.rating,
      );

  String get signature =>
      '$types|${(genres.toList()..sort()).join(",")}'
      '|${(countries.toList()..sort()).join(",")}|${year ?? ''}|${allStatus ?? ''}';
}

/// The collections surfaced by Обзор and Закладки → Коллекции.
class Curated {
  const Curated._();

  static const List<CuratedCollection> all = <CuratedCollection>[
    CuratedCollection(
      id: 'korea',
      title: 'Корейские дорамы',
      subtitle: 'Классика и новинки Кореи',
      countries: <String>{'Корея Южная'},
    ),
    CuratedCollection(
      id: 'china',
      title: 'Китайские дорамы',
      subtitle: 'Историческое и современное',
      countries: <String>{'Китай'},
    ),
    CuratedCollection(
      id: 'turkey',
      title: 'Турецкие сериалы',
      subtitle: 'Драмы и романтика',
      countries: <String>{'Турция'},
    ),
    CuratedCollection(
      id: 'thai',
      title: 'Тайские дорамы',
      subtitle: 'BL, романтика, триллеры',
      countries: <String>{'Таиланд'},
    ),
    CuratedCollection(
      id: 'japan',
      title: 'Японские дорамы',
      subtitle: 'Сериалы из Японии',
      countries: <String>{'Япония'},
    ),
    CuratedCollection(
      id: 'melodrama',
      title: 'Мелодрамы',
      subtitle: 'Сериалы о любви и отношениях',
      genres: <String>{'мелодрама'},
    ),
    CuratedCollection(
      id: 'detective',
      title: 'Детективы',
      subtitle: 'Расследования и тайны',
      genres: <String>{'детектив'},
    ),
    CuratedCollection(
      id: 'thriller',
      title: 'Триллеры',
      subtitle: 'Держит в напряжении',
      genres: <String>{'триллер'},
    ),
    CuratedCollection(
      id: 'comedy',
      title: 'Комедии',
      subtitle: 'Для отдыха',
      genres: <String>{'комедия'},
    ),
    CuratedCollection(
      id: 'fantasy',
      title: 'Фэнтези',
      subtitle: 'Магия и другие миры',
      genres: <String>{'фэнтези'},
    ),
    CuratedCollection(
      id: 'crime',
      title: 'Криминал',
      subtitle: 'Мафия, полиция, преступления',
      genres: <String>{'криминал'},
    ),
    CuratedCollection(
      id: 'ongoing',
      title: 'Сейчас выходят',
      subtitle: 'Сериалы со статусом «Выходит» в Kodik',
      allStatus: 'ongoing',
    ),
    CuratedCollection(
      id: 'movies',
      title: 'Фильмы',
      subtitle: 'Полнометражное кино',
      types: KodikCatalog.movies,
    ),
    CuratedCollection(
      id: 'fresh',
      title: 'Новинки 2026',
      subtitle: 'Произведения 2026 года',
      year: 2026,
    ),
  ];

  static CuratedCollection? byId(String id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
