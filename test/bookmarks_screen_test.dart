import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/bookmarks/bookmarks_screen.dart';

const _favorite = SavedTitleRef(
  id: 'favorite-a',
  title: 'Избранный тайтл A',
  type: 'foreign-serial',
);
const _history = SavedTitleRef(
  id: 'history-b',
  title: 'Тайтл из истории B',
  type: 'foreign-serial',
);
const _watching = SavedTitleRef(
  id: 'watching-c',
  title: 'Просматриваемый тайтл C',
  type: 'foreign-serial',
);
const _planned = SavedTitleRef(
  id: 'planned-d',
  title: 'Запланированный тайтл D',
  type: 'foreign-serial',
);

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: const Scaffold(body: BookmarksScreen()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('switching between favorites and history reloads their own rows',
      (tester) async {
    await Library.toggleFavorite(_favorite);
    await Library.record(WatchEntry(
      title: _history,
      episode: 1,
      watchedAt: DateTime(2026, 10, 10),
    ));
    await _pumpScreen(tester);

    expect(find.text(_favorite.title), findsOneWidget);
    expect(find.text(_history.title), findsNothing);

    await _selectTab(tester, 'История');
    expect(find.text(_history.title), findsOneWidget);
    expect(find.text(_favorite.title), findsNothing);

    await _selectTab(tester, 'Избранное');
    expect(find.text(_favorite.title), findsOneWidget);
    expect(find.text(_history.title), findsNothing);
  });

  testWidgets('each watch-status tab loads only its own saved titles',
      (tester) async {
    await Library.toggleFavorite(_favorite);
    await Library.setWatchStatus(_watching, WatchStatus.watching);
    await Library.setWatchStatus(_planned, WatchStatus.plans);
    await _pumpScreen(tester);

    await _selectTab(tester, WatchStatus.watching.title);
    expect(find.text(_watching.title), findsOneWidget);
    expect(find.text(_planned.title), findsNothing);
    expect(find.text(_favorite.title), findsNothing);

    await _selectTab(tester, WatchStatus.plans.title);
    expect(find.text(_planned.title), findsOneWidget);
    expect(find.text(_watching.title), findsNothing);
    expect(find.text(_favorite.title), findsNothing);

    await _selectTab(tester, WatchStatus.watching.title);
    expect(find.text(_watching.title), findsOneWidget);
    expect(find.text(_planned.title), findsNothing);
  });

  testWidgets('history distinguishes seasons and keeps checkpoint metadata',
      (tester) async {
    await Library.record(WatchEntry(
      title: _history,
      season: 1,
      episode: 1,
      positionMs: 125000,
      watchedAt: DateTime(2026, 10, 10),
    ));
    await Library.record(WatchEntry(
      title: _history,
      season: 2,
      episode: 1,
      watchedAt: DateTime(2026, 10, 11),
    ));
    await _pumpScreen(tester);
    await _selectTab(tester, 'История');

    expect(find.text(_history.title), findsNWidgets(2));
    expect(find.text('Сезон 1 · Серия 1\nПозиция 2:05'), findsOneWidget);
    expect(find.text('Сезон 2 · Серия 1\nНачало серии или позиция не сохранена'), findsOneWidget);
  });
}
