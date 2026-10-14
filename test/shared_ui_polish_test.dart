import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/root.dart';
import 'package:dramix/ui/widgets.dart';

Widget surface(Widget child, {double scale = 2}) => MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 280, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('catalog row wraps metadata and has no inert menu', (tester) async {
    var opened = false;
    await tester.pumpWidget(surface(ReleaseListItem(
      title: 'Длинное название дорамы с несколькими сезонами',
      meta: '2026 · 128 серий · Озвучка на русском языке',
      grade: 8.4,
      ratingSource: 'Кинопоиск',
      onTap: () => opened = true,
    )));
    expect(tester.takeException(), isNull);
    expect(find.text('8.4 ★ · Кинопоиск'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await tester.tap(find.text('Длинное название дорамы с несколькими сезонами'));
    expect(opened, isTrue);
  });

  testWidgets('primary action grows with scaled long text', (tester) async {
    var called = 0;
    await tester.pumpWidget(surface(LightPillButton(
      label: 'Выбрать озвучку и продолжить просмотр',
      icon: Icons.play_arrow,
      onTap: () => called++,
    )));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Выбрать озвучку и продолжить просмотр'));
    expect(called, 1);
    await tester.pumpWidget(surface(LightPillButton(
      label: 'Выбрать озвучку и продолжить просмотр',
      loading: true,
      onTap: () => called++,
    )));
    await tester.tap(find.byType(LightPillButton));
    expect(called, 1);
  });

  testWidgets('tabs keep full tap targets with text scaling', (tester) async {
    var selected = 0;
    await tester.pumpWidget(surface(UnderlineTabs(
      tabs: const ['История', 'Смотрю'],
      selected: 0,
      onChanged: (value) => selected = value,
      separator: 8,
    )));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Смотрю'));
    expect(selected, 1);
    expect(tester.getSize(find.byType(UnderlineTabs)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('page title fits narrow scaled header', (tester) async {
    await tester.pumpWidget(surface(const SizedBox(
      height: 400,
      child: PageScaffold(
        title: 'Сериалы с высоким рейтингом',
        body: SizedBox(),
      ),
    )));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Назад'), findsOneWidget);
  });

  testWidgets('top search and update controls have working targets', (tester) async {
    var searches = 0;
    await tester.pumpWidget(surface(TopBar(
      searchHint: 'Найти дораму или сериал',
      onSearch: () => searches++,
    )));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Найти дораму или сериал'));
    expect(searches, 1);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    expect(find.byTooltip('Обновления каталога'), findsOneWidget);
  });
}
