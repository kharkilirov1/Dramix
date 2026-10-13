import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/home/home_shelves.dart';

const _title = KodikTitle(
  id: 'serial-home', type: 'foreign-serial', title: 'Дорама',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('a failed shelf retries independently', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CatalogShelf(
        heading: 'Подборка',
        loader: () async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return [_title];
        },
        onSeeAll: () {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить подборку'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Дорама'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shelf fits a narrow window and opens complete results',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: CatalogShelf(
        heading: 'Сериалы с высоким рейтингом',
        loader: () async => [_title],
        onSeeAll: () => opened = true,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Все'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continue shelf disappears after clearing local history',
      (tester) async {
    await Library.record(WatchEntry(
      title: _title.ref, season: 2, episode: 3, positionMs: 60000,
      watchedAt: DateTime(2026, 1, 1),
    ));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ContinueWatchingShelf(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Продолжить просмотр'), findsOneWidget);
    expect(find.text('Сезон 2 · Серия 3'), findsOneWidget);
    expect(find.textContaining('секунд'), findsNothing);
    await Library.clearHistory();
    await tester.pumpAndSettle();
    expect(find.text('Продолжить просмотр'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an opened-only episode is not offered as progress',
      (tester) async {
    await Library.record(WatchEntry(
      title: _title.ref, season: 1, episode: 1,
      watchedAt: DateTime(2026, 1, 1),
    ));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ContinueWatchingShelf(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Продолжить просмотр'), findsNothing);
  });

  testWidgets('empty guest history hides continue shelf', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ContinueWatchingShelf(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Продолжить просмотр'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
