import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/net.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/backend_dialog.dart';
import 'package:dramix/ui/settings/settings_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Net.load();
  });

  Future<void> openServerDialog(WidgetTester tester,
      {TextScaler scaler = TextScaler.noScaling}) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: child!,
      ),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => configureBackend(context),
        child: const Text('Настроить'),
      ))),
    ));
    await tester.tap(find.text('Настроить'));
    await tester.pumpAndSettle();
  }

  testWidgets('server dialog fits narrow large-text layout and cancels',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await Net.setBackend('https://dramix.example');
    await openServerDialog(tester, scaler: const TextScaler.linear(2));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(Net.backendOrigin?.host, 'dramix.example');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server validation stays in dialog and retains current routing',
      (tester) async {
    await Net.setBackend('https://dramix.example');
    await openServerDialog(tester);
    await tester.enterText(find.byType(TextField), 'http://untrusted.example');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(Net.backendOrigin?.host, 'dramix.example');
    expect(find.textContaining('Укажите HTTPS-адрес'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clearing server field restores existing guest routing',
      (tester) async {
    await Net.set(mode: NetMode.wrap, template: Net.allOrigins);
    await Net.setBackend('https://dramix.example');
    await openServerDialog(tester);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(Net.backendOrigin, isNull);
    expect(Net.mode, NetMode.wrap);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('local clear confirmation can cancel without losing progress',
      (tester) async {
    await Net.setBackend('https://dramix.example');
    await Library.record(WatchEntry(
      title: const SavedTitleRef(id: 'serial-settings', title: 'Дорама'),
      season: 1, episode: 2, positionMs: 12000,
      watchedAt: DateTime(2026, 1, 1),
    ));
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Очистить историю просмотра'), 300);
    await tester.tap(find.text('Очистить историю просмотра'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Она не удаляет данные на вашем сервере.'),
        findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect((await Library.history()).single.positionMs, 12000);
    expect(tester.takeException(), isNull);
  });
}
