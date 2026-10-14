import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/player/player_screen.dart';
import 'package:dramix/ui/release/voiceover_screen.dart';

KodikTitle _title() => KodikTitle.fromJson({
      'id': 'serial-seasons',
      'type': 'foreign-serial',
      'title': 'Несколько сезонов',
      'seasons': {
        '1': {
          'episodes': {'1': '', '2': ''}
        },
        '2': {
          'episodes': {'1': '', '2': ''}
        },
      },
    });

Future<void> _open(WidgetTester tester, {int? season}) async {
  await tester.pumpWidget(MaterialApp(
    home: EpisodesScreen(title: _title(), initialSeason: season),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('season picker separates repeated episode numbers', (tester) async {
    await _open(tester, season: 2);
    expect(find.text('Сезон 2 · Серия 1'), findsOneWidget);
    expect(find.text('Сезон 1 · Серия 1'), findsNothing);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сезон 1').last);
    await tester.pumpAndSettle();
    expect(find.text('Сезон 1 · Серия 1'), findsOneWidget);
    expect(find.text('Сезон 2 · Серия 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reversed display keeps chronological playback and exact season',
      (tester) async {
    await _open(tester, season: 2);
    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pump();
    await tester.tap(find.text('Сезон 2 · Серия 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final player = tester.widget<PlayerScreen>(find.byType(PlayerScreen));
    expect(player.initialIndex, 3);
    expect(player.episodes[player.initialIndex].season, 2);
    expect(player.episodes[player.initialIndex].episode, 2);
    expect(player.episodes.first.season, 1);
    expect(player.episodes.first.episode, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('jumping ahead does not mark earlier episodes viewed',
      (tester) async {
    await Library.record(WatchEntry(
      title: _title().ref,
      season: 2,
      episode: 2,
      positionMs: 60000,
      watchedAt: DateTime(2026, 1, 1),
    ));
    await _open(tester);
    expect(find.text('Сезон 2 · Серия 1'), findsOneWidget);
    expect(find.text('Начат просмотр'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one-episode serial remains a series', (tester) async {
    final title = KodikTitle.fromJson({
      'id': 'serial-single',
      'type': 'foreign-serial',
      'title': 'Одна серия',
      'seasons': {
        '1': {
          'episodes': {'1': ''}
        },
      },
    });
    await tester.pumpWidget(MaterialApp(home: EpisodesScreen(title: title)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Сезон 1 · Серия 1'), findsOneWidget);
    expect(find.text('Полнометражный фильм'), findsNothing);
  });
}
