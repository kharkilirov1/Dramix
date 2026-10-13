import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/player/player_screen.dart';

const _title = KodikTitle(
  id: 'serial-progress',
  type: 'foreign-serial',
  title: 'Сохранённый просмотр',
);

const _episodes = <KodikEpisodeRef>[
  KodikEpisodeRef(season: 1, episode: 1, url: ''),
];

WatchEntry _checkpoint(int positionMs, {int episode = 1}) => WatchEntry(
      title: _title.ref,
      season: 1,
      episode: episode,
      positionMs: positionMs,
      watchedAt: DateTime(2024, 1, 1),
    );

Future<void> _openUnavailablePlayer(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: PlayerScreen(title: _title, episodes: _episodes),
  ));
  await tester.pump();
  expect(find.text('Ссылка на серию отсутствует'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('opening and closing an unavailable episode creates no history',
      (tester) async {
    await _openUnavailablePlayer(tester);
    expect(await Library.history(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(await Library.history(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying an unavailable episode does not mark it watched',
      (tester) async {
    await _openUnavailablePlayer(tester);
    await tester.tap(find.text('Повторить'));
    await tester.pump();
    expect(await Library.history(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unavailable player preserves the exact saved checkpoint',
      (tester) async {
    await Library.record(_checkpoint(60000));
    await _openUnavailablePlayer(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final resume = await Library.resumePoint(_title.id);
    expect(resume, isNotNull);
    expect(resume!.positionMs, 60000);
    expect(resume.watchedAt, DateTime(2024, 1, 1));
  });

  testWidgets('opening an older episode does not reorder history',
      (tester) async {
    await Library.record(_checkpoint(60000));
    await Library.record(_checkpoint(90000, episode: 2));
    await _openUnavailablePlayer(tester);
    final history = await Library.history();
    expect(history, hasLength(2));
    expect(history.first.episode, 2);
    expect(history.first.positionMs, 90000);
    expect(history.last.episode, 1);
    expect(history.last.positionMs, 60000);
  });

  testWidgets('a different episode checkpoint does not create a false entry',
      (tester) async {
    await Library.record(_checkpoint(90000, episode: 2));
    await _openUnavailablePlayer(tester);
    final history = await Library.history();
    expect(history, hasLength(1));
    expect(history.single.episode, 2);
    expect(history.single.positionMs, 90000);
  });
}
