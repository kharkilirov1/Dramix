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

// An unavailable URL exercises the real opening and disposal paths without
// creating a platform WebView or a native video controller.
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

  testWidgets('opening without a native position preserves the checkpoint',
      (tester) async {
    await Library.record(_checkpoint(60000));

    await _openUnavailablePlayer(tester);

    final resume = await Library.resumePoint(_title.id);
    expect(resume, isNotNull);
    expect(resume!.positionMs, 60000);
  });

  testWidgets('disposing without a native position preserves the checkpoint',
      (tester) async {
    await _openUnavailablePlayer(tester);
    // Seed after opening so this assertion isolates the disposal write.
    await Library.record(_checkpoint(90000));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final resume = await Library.resumePoint(_title.id);
    expect(resume, isNotNull);
    expect(resume!.positionMs, 90000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finds the same episode behind a newer different checkpoint',
      (tester) async {
    await Library.record(_checkpoint(60000));
    await Library.record(_checkpoint(90000, episode: 2));

    await _openUnavailablePlayer(tester);

    final resume = await Library.resumePoint(_title.id);
    expect(resume, isNotNull);
    expect(resume!.episode, 1);
    expect(resume.positionMs, 60000);
  });

  testWidgets('does not copy a different episode position into a new episode',
      (tester) async {
    await Library.record(_checkpoint(90000, episode: 2));

    await _openUnavailablePlayer(tester);

    final history = await Library.history();
    expect(history, hasLength(2));
    expect(history.first.episode, 1);
    expect(history.first.positionMs, 0);
    expect(history.last.episode, 2);
    expect(history.last.positionMs, 90000);
  });
}
