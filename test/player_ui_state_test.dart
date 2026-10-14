import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dramix/core/models.dart';
import 'package:dramix/ui/player/player_screen.dart';

void main() {
  const title = KodikTitle(id: 'serial-test', type: 'foreign-serial',
    title: 'Дорама', translation: KodikTranslation(id: 1, title: 'Студия'));
  testWidgets('empty player offers return instead of impossible retry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:
      PlayerScreen(title: title, episodes: [])));
    await tester.pumpAndSettle();
    expect(find.text('Нет доступной серии'), findsOneWidget);
    expect(find.text('Вернуться к выбору серии'), findsOneWidget);
    expect(find.text('Повторить'), findsNothing);
    expect(find.text('Озвучка · Студия'), findsOneWidget);
    expect(find.byTooltip('Вернуться в веб-плеер'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('duplicate episode numbers remain distinguishable by season', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: PlayerScreen(title: title, episodes: [
        KodikEpisodeRef(season: 1, episode: 1, url: ''),
        KodikEpisodeRef(season: 2, episode: 1, url: ''),
      ]))));
    await tester.pumpAndSettle();
    expect(find.text('Сезон 1'), findsOneWidget);
    expect(find.text('Сезон 2'), findsOneWidget);
    expect(find.text('Серия 1'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('short landscape uses an accessible picker without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(640, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2)),
      child: PlayerScreen(title: title, episodes: [
        KodikEpisodeRef(season: 1, episode: 1, url: ''),
        KodikEpisodeRef(season: 2, episode: 1, url: ''),
      ]))));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Выбрать сезон и серию'), findsOneWidget);
    expect(find.text('Сезон 1'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Выбрать сезон и серию'));
    await tester.pumpAndSettle();
    expect(find.text('Сезон 2 · Серия 1'), findsOneWidget);
    await tester.tap(find.text('Сезон 2 · Серия 1'));
    await tester.pumpAndSettle();
    expect(find.text('Сезон 2 · Серия 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

}
