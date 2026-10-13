import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/storage.dart';
import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/filter/filter_screen.dart';
import 'package:dramix/ui/search/search_screen.dart';
import 'package:dramix/ui/widgets.dart';

Widget _host() => MaterialApp(
      theme: buildTheme(),
      home: const SearchScreen(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('search button submits the query without a keyboard',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Винченцо');
    expect(find.byTooltip('Найти'), findsOneWidget);
    await tester.tap(find.byTooltip('Найти'));
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(PagedScroll), findsOneWidget);
    expect(await Library.searchHistory(), contains('Винченцо'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('filter action opens the existing filter screen', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FilterScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applying a filter opens its results', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FilterScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Применить'), 300);
    await tester.tap(find.text('Применить'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(FilteredResultsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scope tabs fit a narrow web window', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(tester.takeException(), isNull);
    final all = find.text('Всё');
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
