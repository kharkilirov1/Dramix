import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/playback_provider.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/player/player_embed.dart';
import 'package:dramix/ui/player/player_screen.dart';

const _title = KodikTitle(
    id: 'serial-events', type: 'foreign-serial', title: 'События просмотра');
const _episodes = [
  KodikEpisodeRef(season: 1, episode: 1,
      url: 'https://kodikplayer.com/seria/1/test/720p'),
  KodikEpisodeRef(season: 1, episode: 2,
      url: 'https://kodikplayer.com/seria/2/test/720p'),
];

Future<PlayerEmbed> _open(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: PlayerScreen(
      title: _title, episodes: _episodes)));
  await tester.pumpAndSettle();
  return tester.widget<PlayerEmbed>(find.byType(PlayerEmbed));
}

void _event(PlayerEmbed embed, PlaybackEventKind kind, int sequence,
    {int? position, int? episode}) {
  embed.onEvent!(PlaybackEvent(
      sessionId: embed.sessionId, sequence: sequence, kind: kind,
      positionMs: position, season: 1, episode: episode));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('page loading and position without play create no history',
      (tester) async {
    final embed = await _open(tester);
    embed.onLoaded?.call();
    _event(embed, PlaybackEventKind.time, 1, position: 60000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(await Library.history(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed play and time save the exact episode on pause',
      (tester) async {
    final embed = await _open(tester);
    _event(embed, PlaybackEventKind.play, 1);
    _event(embed, PlaybackEventKind.time, 2, position: 60000);
    _event(embed, PlaybackEventKind.pause, 3, position: 61000);
    await tester.pumpAndSettle();
    final history = await Library.history();
    expect(history, hasLength(1));
    expect(history.single.season, 1);
    expect(history.single.episode, 1);
    expect(history.single.positionMs, 61000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('old iframe callbacks cannot write progress after episode switch',
      (tester) async {
    final old = await _open(tester);
    _event(old, PlaybackEventKind.play, 1);
    _event(old, PlaybackEventKind.time, 2, position: 30000);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    final current = tester.widget<PlayerEmbed>(find.byType(PlayerEmbed));
    expect(current.sessionId, isNot(old.sessionId));
    _event(old, PlaybackEventKind.time, 3, position: 90000);
    _event(current, PlaybackEventKind.time, 1, position: 12000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final history = await Library.history();
    expect(history, hasLength(1));
    expect(history.single.episode, 1);
    expect(history.single.positionMs, 30000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-frame episode mismatch suspends the original checkpoint',
      (tester) async {
    final embed = await _open(tester);
    _event(embed, PlaybackEventKind.play, 1);
    _event(embed, PlaybackEventKind.time, 2, position: 30000);
    _event(embed, PlaybackEventKind.episodeChanged, 3, episode: 2);
    _event(embed, PlaybackEventKind.time, 4, position: 90000);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final history = await Library.history();
    expect(history.single.episode, 1);
    expect(history.single.positionMs, 30000);
    expect(tester.takeException(), isNull);
  });
}
