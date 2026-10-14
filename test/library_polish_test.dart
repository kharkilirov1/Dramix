import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/bookmarks/bookmarks_screen.dart';
import 'package:dramix/ui/bookmarks/library_row.dart';

const alpha = SavedTitleRef(id: 'a', title: 'Альфа');
const zeta = SavedTitleRef(id: 'z', title: 'Яркая дорама');

Future<void> openLibrary(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: const Scaffold(body: BookmarksScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('local search changes visible rows without changing saved data', (tester) async {
    await Library.toggleFavorite(alpha);
    await Library.toggleFavorite(zeta);
    await openLibrary(tester);
    await tester.enterText(find.byKey(const ValueKey<String>('library-search')), 'альфа');
    await tester.pumpAndSettle();
    expect(find.text(alpha.title), findsOneWidget);
    expect(find.text(zeta.title), findsNothing);
    expect(find.text('Записей: 1'), findsOneWidget);
    expect(await Library.favorites(), hasLength(2));
    await tester.enterText(find.byKey(const ValueKey<String>('library-search')), 'нет такого');
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await tester.tap(find.text('Сбросить поиск'));
    await tester.pumpAndSettle();
    expect(find.text(zeta.title), findsOneWidget);
  });

  testWidgets('title sorting is functional and does not reorder storage', (tester) async {
    await Library.toggleFavorite(alpha);
    await Library.toggleFavorite(zeta);
    await openLibrary(tester);
    expect(tester.getTopLeft(find.text(zeta.title)).dy,
      lessThan(tester.getTopLeft(find.text(alpha.title)).dy));
    await tester.tap(find.byKey(const ValueKey<String>('library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('По названию').last);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text(alpha.title)).dy,
      lessThan(tester.getTopLeft(find.text(zeta.title)).dy));
    expect((await Library.favorites()).first.id, zeta.id);
  });

  testWidgets('history clearing requires confirmation and preserves favorites', (tester) async {
    await Library.toggleFavorite(alpha);
    await Library.record(WatchEntry(title: alpha, season: 1, episode: 2,
      positionMs: 45000, watchedAt: DateTime(2026, 10, 14)));
    await openLibrary(tester);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Облачные данные не изменятся'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(await Library.history(), hasLength(1));
    await tester.tap(find.byTooltip('Очистить историю'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Очистить'));
    await tester.pumpAndSettle();
    expect(await Library.history(), isEmpty);
    expect(await Library.favorites(), hasLength(1));
    expect(find.text('История пуста'), findsOneWidget);
    expect(find.text('Найти дораму'), findsOneWidget);
  });

  testWidgets('history row supports narrow width and enlarged text with honest zero', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = WatchEntry(title: alpha, season: 2, episode: 8,
      watchedAt: DateTime(2026, 10, 14));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          LibraryRow(title: alpha, checkpoint: entry, onOpen: () {}),
        ]),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Сезон 2 · Серия 8'), findsOneWidget);
    expect(find.textContaining('Начало серии или позиция не сохранена'), findsOneWidget);
    expect(find.text('Открыть карточку'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('library controls scroll at 320 width with large text and keyboard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await Library.toggleFavorite(alpha);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const MediaQuery(
        data: MediaQueryData(
          size: Size(320, 480),
          viewInsets: EdgeInsets.only(bottom: 240),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(body: BookmarksScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey<String>('library-search'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'альфа');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((await Library.favorites()).single.id, alpha.id);
    await tester.drag(find.byKey(const ValueKey<String>('library-scroll')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text(alpha.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
