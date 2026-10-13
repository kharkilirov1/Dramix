import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/release/voiceover_screen.dart';

KodikTitle _version(String id, {String work = '123', String name = 'Дорама'}) =>
    KodikTitle.fromJson({
      'id': id,
      'type': 'foreign-serial',
      'title': name,
      'kinopoisk_id': work,
      'seasons': {
        '2': {
          'episodes': {'1': '', '2': ''}
        },
      },
    });

WatchEntry _entry(SavedTitleRef title, {int episode = 2, int ms = 60000}) =>
    WatchEntry(title: title, season: 2, episode: episode, positionMs: ms,
        watchedAt: DateTime(2026, 1, 1));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('episode screen learns its identity and reads another dub history',
      (tester) async {
    final first = _version('serial-first');
    final selected = _version('serial-selected');
    await Library.registerTitle(first.ref);
    // Legacy snapshot has no external ID; the registered alias must resolve it.
    await Library.record(_entry(const SavedTitleRef(
        id: 'serial-first', title: 'Дорама', type: 'foreign-serial')));
    await tester.pumpWidget(MaterialApp(
      home: EpisodesScreen(title: selected),
    ));
    await tester.pumpAndSettle();
    expect(await Library.workId(selected.id), first.ref.workId);
    expect(find.text('Начат просмотр'), findsOneWidget);
    expect(find.text('Сезон 2 · Серия 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('same name with different work IDs does not share episode markers',
      () async {
    final first = _version('serial-first');
    final unrelated = _version('serial-other', work: '456');
    await Library.registerTitle(first.ref);
    await Library.registerTitle(unrelated.ref);
    final markers = await startedEpisodesForWork(
        unrelated.ref, [_entry(first.ref)]);
    expect(markers, isEmpty);
  });

  test('latest zero checkpoint wins over older progress in another dub',
      () async {
    final first = _version('serial-first');
    final second = _version('serial-second');
    await Library.registerTitle(first.ref);
    await Library.registerTitle(second.ref);
    final markers = await startedEpisodesForWork(second.ref, [
      _entry(second.ref, ms: 0),
      _entry(first.ref),
      _entry(first.ref, episode: 1),
    ]);
    expect(markers, {'2:1'});
  });
}
