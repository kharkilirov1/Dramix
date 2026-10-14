import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/home/home_shelves.dart';
import 'package:dramix/ui/widgets.dart';

KodikTitle _title({String name = 'Дорама', bool metadata = true}) =>
    KodikTitle.fromJson({
      'id': 'serial-polish',
      'type': 'foreign-serial',
      'title': name,
      if (metadata) 'year': 2021,
      if (metadata)
        'material_data': {
          'description': '<p>История о любви и дружбе.</p>',
          'countries': ['Корея Южная'],
          'all_genres': ['мелодрама'],
          'kinopoisk_rating': 8.4,
        },
    });

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      home: Builder(builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      )),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('featured panel fits a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    await tester.pumpWidget(_host(CatalogShelf(
      heading: 'Недавно обновлённые',
      subtitle: 'Последние изменения в каталоге',
      featured: true,
      loader: () async => [_title(name: 'Очень длинное название дорамы')],
      onSeeAll: () => opened = true,
    ), scale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Кинопоиск 8.4'), findsOneWidget);
    expect(find.text('История о любви и дружбе.'), findsOneWidget);
    expect(find.text('Подробнее'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Все'));
    await tester.tap(find.text('Все'));
    expect(opened, isTrue);
  });

  testWidgets('wide featured panel places details beside the artwork',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(CatalogShelf(
      heading: 'Недавно обновлённые', featured: true,
      loader: () async => [_title()], onSeeAll: () {},
    )));
    await tester.pumpAndSettle();
    final artwork = tester.getRect(find.byType(RemoteImage));
    final title = tester.getRect(find.text('Дорама'));
    expect(title.left, greaterThan(artwork.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured panel omits missing ratings and description',
      (tester) async {
    await tester.pumpWidget(_host(CatalogShelf(
      heading: 'Недавно обновлённые',
      featured: true,
      loader: () async => [_title(metadata: false)],
      onSeeAll: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Дорама'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.textContaining('Кинопоиск'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading then empty shelf preserves access to the catalog',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final pending = Completer<List<KodikTitle>>();
    var opened = false;
    await tester.pumpWidget(_host(CatalogShelf(
      heading: 'Мелодрамы',
      loader: () => pending.future,
      onSeeAll: () => opened = true,
    )));
    await tester.pump();
    expect(find.bySemanticsLabel('Загружаем подборку'), findsOneWidget);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('Здесь пока пусто'), findsOneWidget);
    await tester.tap(find.text('Все'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry affects only the failed shelf', (tester) async {
    var failedCalls = 0;
    var goodCalls = 0;
    await tester.pumpWidget(_host(Column(children: [
      CatalogShelf(
        heading: 'Обновления',
        loader: () async {
          failedCalls++;
          if (failedCalls == 1) throw StateError('offline');
          return [_title(name: 'Восстановленная подборка')];
        },
        onSeeAll: () {},
      ),
      CatalogShelf(
        heading: 'Мелодрамы',
        loader: () async {
          goodCalls++;
          return [_title(name: 'Доступная подборка')];
        },
        onSeeAll: () {},
      ),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось загрузить подборку'), findsOneWidget);
    expect(find.text('Доступная подборка'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Восстановленная подборка'), findsOneWidget);
    expect(goodCalls, 1);
    expect(failedCalls, 2);
  });

  testWidgets('continuation keeps episode context and accessible action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(ContinueWatchingShelf(loader: () async => [
      WatchEntry(
        title: _title(name: 'Очень длинное название дорамы').ref,
        season: 2, episode: 3, positionMs: 60000,
        watchedAt: DateTime(2026, 1, 1),
      ),
    ]), scale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Сезон 2 · Серия 3'), findsOneWidget);
    final action = find.bySemanticsLabel(RegExp(
        'Очень длинное название дорамы.*Сезон 2.*Серия 3.*'));
    final node = tester.getSemantics(action);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed history retries without requiring an account',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(ContinueWatchingShelf(loader: () async {
      calls++;
      if (calls == 1) throw StateError('unavailable storage');
      return [];
    })));
    await tester.pumpAndSettle();
    expect(find.text('Не удалось прочитать историю'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Продолжить просмотр'), findsNothing);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
