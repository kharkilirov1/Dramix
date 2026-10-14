import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/bookmarks/bookmarks_screen.dart';
import 'package:dramix/ui/collections/collections_screen.dart';
import 'package:dramix/ui/discover/discover_screen.dart';
import 'package:dramix/ui/filter/filter_screen.dart';
import 'package:dramix/ui/home/home_screen.dart';
import 'package:dramix/ui/notifications/notifications_screen.dart';
import 'package:dramix/ui/popular/popular_screen.dart';
import 'package:dramix/ui/profile/profile_screen.dart';
import 'package:dramix/ui/root.dart';
import 'package:dramix/ui/schedule/schedule_screen.dart';
import 'package:dramix/ui/search/search_screen.dart';
import 'package:dramix/ui/settings/settings_screen.dart';

/// Build smoke tests.
///
/// `flutter_test` stubs the network (every request answers 400), which is
/// exactly the "offline / no token" path each screen has to survive. These
/// tests assert that every screen builds its widget tree and reaches a state
/// without throwing — the cheapest way to catch a broken screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final screens = <String, Widget>{
    'HomeScreen': const HomeScreen(),
    'DiscoverScreen': const DiscoverScreen(),
    'BookmarksScreen': const BookmarksScreen(),
    'ProfileScreen': const ProfileScreen(),
    'SearchScreen': const SearchScreen(),
    'FilterScreen': const FilterScreen(),
    'SettingsScreen': const SettingsScreen(),
    'PopularScreen': const PopularScreen(),
    'ScheduleScreen': const ScheduleScreen(),
    'CollectionsScreen': const CollectionsScreen(),
    'NotificationsScreen': const NotificationsScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} builds offline without throwing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: entry.value,
      ));
      await tester.pump(const Duration(milliseconds: 60));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('RootShell mounts all four tabs at once', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const RootShell(),
    ));
    await tester.pump(const Duration(milliseconds: 60));

    // IndexedStack builds every tab, so a broken tab fails this test.
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Закладки'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Весь каталог'), findsOneWidget);
    expect(find.text('Моя вкладка'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home retains access to the full catalog and saved filter',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(), home: const RootShell(),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Весь каталог'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CatalogScreen), findsOneWidget);
    expect(find.text('Моя вкладка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RootShell switches tabs on tap', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: const RootShell(),
    ));
    await tester.pump(const Duration(milliseconds: 60));

    await tester.tap(find.text('Закладки'));
    await tester.pump(const Duration(milliseconds: 60));

    // The bookmarks tab owns the longest tab strip in the app.
    expect(find.text('Избранное'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
