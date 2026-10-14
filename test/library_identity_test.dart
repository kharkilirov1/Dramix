import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';

const first = SavedTitleRef(id: 'serial-a', title: 'Drama', kinopoiskId: '123',
    translationId: 1);
const second = SavedTitleRef(id: 'serial-b', title: 'Drama', kinopoiskId: '123',
    translationId: 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('work identity is separate from provider and translation', () {
    expect(first.id, isNot(second.id));
    expect(first.workId, second.workId);
    expect(first.workId, 'kinopoisk:123');
    final restored = SavedTitleRef.fromJson(second.toJson());
    expect(restored.id, second.id);
    expect(restored.workId, first.workId);
    expect(restored.translationId, 2);
  });

  test('unknown and invalid ids never merge by title and year', () {
    expect(titleWorkId('a', kinopoiskId: '0', imdbId: 'null'), 'kodik:a');
    expect(titleWorkId('b', kinopoiskId: '-1'), 'kodik:b');
    expect(titleWorkId('a', imdbId: 'tt123'), 'imdb:tt123');
    expect(titleWorkId('a', mdlId: '12'), 'mdl:12');
    expect(titleWorkId('a', shikimoriId: '42'), 'shikimori:42');
    const a = SavedTitleRef(id: 'a', title: 'Same', year: 2020);
    const b = SavedTitleRef(id: 'b', title: 'Same', year: 2020);
    expect(a.workId, isNot(b.workId));
  });

  test('registration preserves raw legacy data and one immutable backup', () async {
    final old = jsonEncode(const SavedTitleRef(id: 'serial-a', title: 'Old').toJson());
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dramix.favorites': <String>[old],
      'dramix.ratings': '{"serial-a":4}',
      'dramix.history': <String>['{bad json'],
    });
    await Library.registerTitle(first);
    final prefs = await SharedPreferences.getInstance();
    final backup = prefs.getString('dramix.libraryBackup.v1');
    expect(backup, isNotNull);
    expect(jsonDecode(backup!)['dramix.favorites'], [old]);
    expect(prefs.getStringList('dramix.favorites'), [old]);
    expect(prefs.getStringList('dramix.history'), ['{bad json']);
    expect(prefs.getString('dramix.ratings'), '{"serial-a":4}');
    final aliases = prefs.getString('dramix.workAliases.v1');
    await Library.registerTitle(first);
    expect(prefs.getString('dramix.libraryBackup.v1'), backup);
    expect(prefs.getString('dramix.workAliases.v1'), aliases);
    await Library.registerTitle(second);
    expect(await Library.isFavorite(second.id), isTrue);
    expect(await Library.rating(second.id), 4);
    expect(await Library.toggleFavorite(second), isFalse);
    expect(await Library.favorites(), isEmpty);
    expect(prefs.getString('dramix.libraryBackup.v1'), backup);
  });

  test('learned aliases share lists ratings and episode progress', () async {
    await Library.registerTitle(first);
    await Library.registerTitle(second);
    await Library.setWatchStatus(first, WatchStatus.watching);
    await Library.setRating(first.id, 4);
    await Library.record(WatchEntry(title: first, season: 1, episode: 2,
        positionMs: 1000, watchedAt: DateTime(2024)));
    expect(await Library.watchStatus(second.id), WatchStatus.watching.value);
    expect(await Library.rating(second.id), 4);
    expect((await Library.resumePoint(second.id))!.positionMs, 1000);
    await Library.record(WatchEntry(title: second, season: 1, episode: 2,
        positionMs: 2000, watchedAt: DateTime(2024, 2)));
    expect(await Library.history(), hasLength(1));
    expect((await Library.resumePoint(first.workId))!.title.id, second.id);
    await Library.setWatchStatus(second, WatchStatus.completed);
    expect(await Library.list(WatchStatus.watching), isEmpty);
    expect(await Library.list(WatchStatus.completed), hasLength(1));
    await Library.setRating(second.id, 3);
    expect(await Library.rating(first.id), 3);
  });

  test('upgrading a fallback alias preserves ratings and guest resume', () async {
    const old = SavedTitleRef(id: 'serial-a', title: 'Old');
    await Library.registerTitle(old);
    await Library.setRating(old.id, 5);
    await Library.record(WatchEntry(title: old, episode: 1,
        positionMs: 1000, watchedAt: DateTime(2024)));
    await Library.registerTitle(first);
    await Library.registerTitle(second);
    expect(await Library.rating(second.id), 5);
    expect((await Library.resumePoint(second.id))!.title.id, old.id);
    expect(await Library.watchedTitleIds(), contains(second.id));
    expect(await Library.watchedTitleIds(), contains(first.workId));
    await Library.setRating(second.id, 2);
    expect(await Library.rating(first.id), 2);
  });

  test('concurrent registration and records remain serialized', () async {
    await Future.wait([
      Library.registerTitle(first),
      Library.registerTitle(second),
      Library.record(WatchEntry(title: first, episode: 1, watchedAt: DateTime(2024))),
      Library.record(WatchEntry(title: second, episode: 2, watchedAt: DateTime(2024))),
    ]);
    expect(await Library.workId(first.id), await Library.workId(second.id));
    expect(await Library.history(), hasLength(2));
  });

  test('continue watching is latest per work and respects a zero reset', () async {
    await Library.registerTitle(first);
    await Library.registerTitle(second);
    await Library.record(WatchEntry(title: first, episode: 1,
        positionMs: 1000, watchedAt: DateTime(2024)));
    await Library.record(WatchEntry(title: second, episode: 2,
        positionMs: 2000, watchedAt: DateTime(2024)));
    final items = await Library.continueWatching();
    expect(items, hasLength(1));
    expect(items.single.title.id, second.id);
    await Library.record(WatchEntry(title: first, episode: 3,
        watchedAt: DateTime(2024)));
    expect(await Library.continueWatching(), isEmpty);
  });

  test('reads observe mutations queued before them without deadlocking', () async {
    final record = Library.record(WatchEntry(title: first, season: 1, episode: 2,
        positionMs: 1000, watchedAt: DateTime(2024)));
    final history = Library.history();
    expect(await history, hasLength(1));
    await record;
    final favorite = Library.toggleFavorite(first);
    expect(await Library.isFavorite(first.id), isTrue);
    await favorite;
    final status = Library.setWatchStatus(first, WatchStatus.watching);
    expect(await Library.watchStatus(first.id), WatchStatus.watching.value);
    await status;
    final rating = Library.setRating(first.id, 4);
    expect(await Library.rating(first.id), 4);
    await rating;
    await Library.registerTitle(second);
    expect((await Library.episodeCheckpoint(second.id, 1, 2))!.positionMs, 1000);
    expect(await Library.episodeCheckpoint(second.id, 1, 3), isNull);
  });

  test('metadata conflicts do not overwrite an established external alias', () async {
    await Library.registerTitle(first);
    await Library.registerTitle(const SavedTitleRef(
        id: 'serial-a', title: 'Other', kinopoiskId: '999'));
    expect(await Library.workId(first.id), 'kinopoisk:123');
  });

  test('corrupt aliases fail safely without rewriting user stores', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'dramix.workAliases.v1': '{bad',
      'dramix.favorites': <String>['original'],
    });
    await expectLater(Library.registerTitle(first), throwsFormatException);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('dramix.favorites'), ['original']);
    expect(prefs.getString('dramix.workAliases.v1'), '{bad');
    // The queue recovers after failure once the corrupt sidecar is restored.
    await prefs.remove('dramix.workAliases.v1');
    await Library.registerTitle(first);
    expect(await Library.workId(first.id), first.workId);
  });
}
