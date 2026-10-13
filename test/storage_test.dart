import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';

const SavedTitleRef _ref = SavedTitleRef(
  id: 'serial-32799',
  title: 'Винченцо',
  poster: 'https://example.org/p.jpg',
  type: 'foreign-serial',
  year: 2021,
  episodes: 20,
);

WatchEntry _entry(int episode, DateTime at, {int positionMs = 0}) => WatchEntry(
      title: _ref,
      season: 1,
      episode: episode,
      positionMs: positionMs,
      watchedAt: at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('LibraryStats watch time', () {
    for (final sample in <int, int>{
      1439: 0,
      1440: 0,
      86399: 0,
      86400: 1,
      172800: 2,
    }.entries) {
      test('${sample.key} seconds is ${sample.value} whole days', () {
        final stats = LibraryStats(watchedSeconds: sample.key);

        expect(stats.watchedDays, sample.value);
      });
    }
  });

  group('Library history', () {
    test('keeps the newest checkpoint first', () async {
      await Library.record(_entry(1, DateTime(2024, 1, 1)));
      await Library.record(_entry(2, DateTime(2024, 1, 2)));

      final history = await Library.history();

      expect(history, hasLength(2));
      expect(history.first.episode, 2);
      expect(history.first.title.title, 'Винченцо');
      expect(history.first.title.year, 2021);
    });

    test('moving back to an earlier episode does not duplicate it', () async {
      await Library.record(_entry(1, DateTime(2024, 1, 1)));
      await Library.record(_entry(2, DateTime(2024, 1, 2)));
      await Library.record(_entry(1, DateTime(2024, 1, 3), positionMs: 120000));

      final history = await Library.history();

      expect(history, hasLength(2));
      expect(history.first.episode, 1);
      expect(history.first.positionMs, 120000);
    });

    test('resumePoint returns the latest checkpoint for a title', () async {
      await Library.record(_entry(1, DateTime(2024, 1, 1)));
      await Library.record(_entry(5, DateTime(2024, 1, 2), positionMs: 60000));

      final resume = await Library.resumePoint('serial-32799');

      expect(resume, isNotNull);
      expect(resume!.episode, 5);
      expect(resume.positionMs, 60000);
      expect(resume.label, 'серия 5');
    });

    test('resumePoint is null for an unknown title', () async {
      expect(await Library.resumePoint('serial-999'), isNull);
    });

    test('clearHistory empties the list', () async {
      await Library.record(_entry(1, DateTime(2024, 1, 1)));
      await Library.clearHistory();

      expect(await Library.history(), isEmpty);
    });

    test('skips a corrupt entry instead of losing the list', () async {
      await Library.record(_entry(1, DateTime(2024, 1, 1)));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('dramix.history')!;
      await prefs
          .setStringList('dramix.history', <String>['{not json', ...raw]);

      final history = await Library.history();

      expect(history, hasLength(1));
      expect(history.single.episode, 1);
    });

    test('bumps revision so mounted screens can refresh', () async {
      var changes = 0;
      void listener() => changes++;
      Library.revision.addListener(listener);
      addTearDown(() => Library.revision.removeListener(listener));

      await Library.record(_entry(1, DateTime(2024, 1, 1)));
      expect(changes, 1, reason: 'record');

      await Library.toggleFavorite(_ref);
      expect(changes, 2, reason: 'toggleFavorite');

      await Library.clearHistory();
      expect(changes, 3, reason: 'clearHistory');
    });
  });

  group('Library favourites', () {
    test('toggle adds then removes', () async {
      expect(await Library.isFavorite(_ref.id), isFalse);

      expect(await Library.toggleFavorite(_ref), isTrue);
      expect(await Library.isFavorite(_ref.id), isTrue);

      final favorites = await Library.favorites();
      expect(favorites.single.title, 'Винченцо');
      expect(favorites.single.subtitle, '2021 · 20 эп.');

      expect(await Library.toggleFavorite(_ref), isFalse);
      expect(await Library.isFavorite(_ref.id), isFalse);
      expect(await Library.favorites(), isEmpty);
    });

    test('clearFavorites empties the list', () async {
      await Library.toggleFavorite(_ref);
      await Library.clearFavorites();

      expect(await Library.favorites(), isEmpty);
    });
  });

  group('SavedTitleRef', () {
    test('round-trips through JSON', () {
      final restored = SavedTitleRef.fromJson(_ref.toJson());

      expect(restored.id, _ref.id);
      expect(restored.title, _ref.title);
      expect(restored.poster, _ref.poster);
      expect(restored.year, 2021);
      expect(restored.episodes, 20);
    });

    test('tolerates a partial payload', () {
      final restored = SavedTitleRef.fromJson(const {'id': 'x-1'});

      expect(restored.id, 'x-1');
      expect(restored.title, 'Без названия');
      expect(restored.subtitle, '');
    });
  });
}
