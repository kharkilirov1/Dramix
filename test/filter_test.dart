import 'package:flutter_test/flutter_test.dart';

import 'package:dramix/core/models.dart';

KodikTitle _title({String id = 'serial-1', double? rating}) => KodikTitle(
      id: id,
      type: 'foreign-serial',
      title: 'Тест',
      material: KodikMaterial(kinopoiskRating: rating),
    );

void main() {
  group('CatalogFilter → server query', () {
    test('serialises multi-country and multi-genre', () {
      final query = CatalogFilter(
        countries: <String>{'Корея Южная', 'Китай'},
        genres: <String>{'драма', 'мелодрама'},
        year: 2024,
        minimalAge: 16,
      ).toQuery();

      expect(query['countries'], contains('Корея Южная'));
      expect(query['countries'], contains('Китай'));
      expect(query['genres']!.split(','), hasLength(2));
      expect(query['year'], '2024');
      expect(query['minimal_age'], '16');
      expect(query['order'], 'desc');
      expect(query['sort'], CatalogSort.updated.value);
    });

    test('omits constraints that are not set', () {
      final query = CatalogFilter(types: KodikCatalog.dramas).toQuery();
      expect(query.containsKey('countries'), isFalse);
      expect(query.containsKey('genres'), isFalse);
      expect(query.containsKey('all_status'), isFalse);
      expect(query.containsKey('year'), isFalse);
      expect(query['types'], KodikCatalog.dramas);
    });

    test('keeps client-side options out of the server query', () {
      final query = CatalogFilter(minRating: 8, hideWatched: true).toQuery();
      expect(query.containsKey('min_rating'), isFalse);
      expect(query.containsKey('hide_watched'), isFalse);
    });
  });

  group('CatalogFilter.accepts', () {
    test('drops titles below the minimum rating', () {
      final filter = CatalogFilter(minRating: 8);
      expect(filter.accepts(_title(rating: 8.5)), isTrue);
      expect(filter.accepts(_title(rating: 7.9)), isFalse);
      expect(filter.accepts(_title()), isFalse,
          reason: 'an unrated title cannot satisfy «от 8»');
    });

    test('hides watched titles when asked', () {
      final filter = CatalogFilter(hideWatched: true);
      expect(filter.accepts(_title(id: 'a'), watched: <String>{'a'}), isFalse);
      expect(filter.accepts(_title(id: 'b'), watched: <String>{'a'}), isTrue);
    });

    test('accepts everything when nothing is constrained', () {
      final filter = CatalogFilter();
      expect(filter.accepts(_title()), isTrue);
      expect(filter.accepts(_title(rating: 1)), isTrue);
      expect(filter.accepts(_title(), watched: <String>{'serial-1'}), isTrue);
    });
  });

  group('CatalogFilter identity', () {
    test('signature reacts to every visual constraint', () {
      final base = CatalogFilter().signature;
      expect(CatalogFilter(countries: <String>{'Китай'}).signature, isNot(base));
      expect(CatalogFilter(genres: <String>{'драма'}).signature, isNot(base));
      expect(CatalogFilter(minRating: 7).signature, isNot(base));
      expect(CatalogFilter(hideWatched: true).signature, isNot(base));
      expect(CatalogFilter(sort: CatalogSort.imdb).signature, isNot(base));
      expect(CatalogFilter(year: 2020).signature, isNot(base));
    });

    test('signature ignores set ordering', () {
      expect(
        CatalogFilter(genres: <String>{'драма', 'комедия'}).signature,
        CatalogFilter(genres: <String>{'комедия', 'драма'}).signature,
      );
      expect(
        CatalogFilter(countries: <String>{'Китай', 'Турция'}).signature,
        CatalogFilter(countries: <String>{'Турция', 'Китай'}).signature,
      );
    });
  });

  group('CatalogFilter JSON round-trip', () {
    test('preserves every field', () {
      final filter = CatalogFilter(
        types: KodikCatalog.movies,
        allStatus: 'ongoing',
        countries: <String>{'Турция'},
        genres: <String>{'драма'},
        year: 2021,
        minimalAge: 18,
        minRating: 7.5,
        hideWatched: true,
        sort: CatalogSort.imdb,
      );

      final restored = CatalogFilter.fromJson(filter.toJson());

      expect(restored.types, filter.types);
      expect(restored.allStatus, 'ongoing');
      expect(restored.countries, <String>{'Турция'});
      expect(restored.genres, <String>{'драма'});
      expect(restored.year, 2021);
      expect(restored.minimalAge, 18);
      expect(restored.minRating, 7.5);
      expect(restored.hideWatched, isTrue);
      expect(restored.sort, CatalogSort.imdb);
      expect(restored.signature, filter.signature);
    });

    test('falls back to defaults on an empty payload', () {
      final restored = CatalogFilter.fromJson(const <String, dynamic>{});
      expect(restored.types, KodikCatalog.dramas);
      expect(restored.sort, CatalogSort.updated);
      expect(restored.isEmpty, isTrue);
    });
  });

  group('CatalogFilter tier gating', () {
    test('marks only the paid controls as advanced', () {
      expect(CatalogFilter().usesAdvancedFilters, isFalse);
      expect(CatalogFilter(year: 2020).usesAdvancedFilters, isFalse);
      expect(CatalogFilter(allStatus: 'ongoing').usesAdvancedFilters, isFalse);
      expect(CatalogFilter(genres: <String>{'драма'}).usesAdvancedFilters, isTrue);
      expect(CatalogFilter(countries: <String>{'Китай'}).usesAdvancedFilters, isTrue);
      expect(CatalogFilter(minRating: 7).usesAdvancedFilters, isTrue);
      expect(CatalogFilter(minimalAge: 16).usesAdvancedFilters, isTrue);
      expect(CatalogFilter(hideWatched: true).usesAdvancedFilters, isTrue);
    });

    test('activeCount counts every constraint', () {
      expect(CatalogFilter().activeCount, 0);
      expect(
        CatalogFilter(
          allStatus: 'ongoing',
          countries: <String>{'Китай'},
          year: 2020,
          hideWatched: true,
        ).activeCount,
        4,
      );
    });

    test('copy is deep for the mutable sets', () {
      final original = CatalogFilter(
        genres: <String>{'драма'},
        countries: <String>{'Китай'},
      );
      final clone = original.copy();
      clone.genres.add('комедия');
      clone.countries.clear();

      expect(original.genres, <String>{'драма'});
      expect(original.countries, <String>{'Китай'});
    });
  });

  group('CatalogSort', () {
    test('exposes the sort keys Kodik documents', () {
      final values = CatalogSort.values.map((s) => s.value).toSet();
      expect(values, contains('updated_at'));
      expect(values, contains('kinopoisk_rating'));
      expect(values, contains('imdb_rating'));
      expect(values, contains('shikimori_rating'));
      expect(values, contains('year'));
      expect(values, contains('created_at'));
    });
  });
}
