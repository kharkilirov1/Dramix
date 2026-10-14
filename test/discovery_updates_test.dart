import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/collections.dart';
import 'package:dramix/core/models.dart';
import 'package:dramix/ui/collections/collections_screen.dart';
import 'package:dramix/ui/discover/discover_screen.dart';
import 'package:dramix/ui/schedule/schedule_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('discovery navigation fits narrow large-text layout', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      routes: {'/schedule': (_) {
        opened = true;
        return const Scaffold(body: Text('Обновления открыты'));
      }},
      home: Scaffold(body: DiscoverScreen(
        bannersLoader: () async => [],
        ongoingLoader: () async => [],
        randomLoader: () async => null,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Обновления по дням'));
    await tester.tap(find.text('Обновления по дням'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed discovery banners retry without hiding navigation',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DiscoverScreen(
      bannersLoader: () async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return [];
      },
      ongoingLoader: () async => [],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Коллекции'), findsOneWidget);
    expect(find.text('Не удалось загрузить тайтлы с высоким рейтингом'),
        findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Не удалось загрузить тайтлы с высоким рейтингом'),
        findsNothing);
  });

  testWidgets('random discovery has one in-flight request and explains no match',
      (tester) async {
    final pending = Completer<KodikTitle?>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DiscoverScreen(
      bannersLoader: () async => [],
      ongoingLoader: () async => [],
      randomLoader: () {
        calls++;
        return pending.future;
      },
    ))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Случайный тайтл'));
    await tester.tap(find.text('Случайный тайтл'));
    await tester.pump();
    expect(find.text('Выбираем тайтл…'), findsOneWidget);
    await tester.tap(find.text('Выбираем тайтл…'));
    expect(calls, 1);
    pending.complete(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Не удалось найти подходящий тайтл. Попробуйте ещё раз.'),
        findsOneWidget);
    expect(find.text('Случайный тайтл'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekday sample initially opens an available day', (tester) async {
    // Choose a day other than today so this checks the initial fallback.
    final date = DateTime.now().subtract(const Duration(days: 1));
    final title = KodikTitle(
      id: 'serial-update', type: 'foreign-serial',
      title: 'Обновлённая дорама', updatedAt: date,
    );
    await tester.pumpWidget(MaterialApp(home: ScheduleScreen(
      loader: () async => KodikPage(total: 1, results: [title]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Обновлённая дорама'), findsOneWidget);
    expect(find.textContaining('это не расписание выхода серий'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekday sample can retry and does not claim no real releases',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: ScheduleScreen(
      loader: () async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return KodikPage.empty;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('В загруженной выборке нет обновлений с указанной датой'),
        findsOneWidget);
    expect(find.text('В этот день обновлений не было'), findsNothing);
  });

  test('collection copy describes actual filters instead of unsupported claims',
      () {
    final japan = collectionDescription(Curated.byId('japan')!);
    final fresh = collectionDescription(Curated.byId('fresh')!);
    final ongoing = collectionDescription(Curated.byId('ongoing')!);
    expect(japan, contains('Япония'));
    expect(japan, isNot(contains('аниме')));
    expect(fresh, contains('Год выпуска: 2026'));
    expect(fresh, isNot(contains('Добавлено')));
    expect(ongoing, isNot(contains('каждую неделю')));
  });
}
