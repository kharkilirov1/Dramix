import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/core/backend_session.dart';
import '../lib/ui/account/account_screen.dart';
import '../lib/ui/profile/profile_screen.dart';

Widget app(Widget screen, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: screen),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('guest account panel never sends requests on open', (tester) async {
    var requests = 0;
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 500);
      }));
    await tester.pumpWidget(app(AccountScreen(origin: session.origin, session: session)));
    await tester.pumpAndSettle();
    expect(find.text('Гостевой режим'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(requests, 0);
    session.close();
  });

  testWidgets('signed-in panel reads pending metadata without cloud request', (tester) async {
    var requests = 0;
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({
          'token': 'fixture-token', 'user_id': 'fixture-user',
          'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch / 1000,
        }), 200);
      }));
    await session.signIn('tester', 'fixture-password');
    final scope = 'dramix.cloud.v1.${Uri.encodeComponent(session.origin.toString())}.fixture-user';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$scope.pending', '[]');
    await tester.pumpWidget(app(AccountScreen(origin: session.origin, session: session)));
    await tester.pumpAndSettle();
    expect(find.text('Незавершённых операций нет'), findsOneWidget);
    final retry = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Повторить незавершённый импорт'));
    expect(retry.onPressed, isNull);
    expect(requests, 1);
    session.close();
  });

  testWidgets('profile presents local checkpoint counts without watch duration claim', (tester) async {
    await tester.pumpWidget(app(const ProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Моя библиотека'), findsOneWidget);
    expect(find.text('Точек в истории'), findsOneWidget);
    expect(find.textContaining('Время просмотра:'), findsNothing);
    expect(find.text('Показать все'), findsNothing);
  });

  testWidgets('profile remains usable at narrow width and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const ProfileScreen(), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Моя библиотека'), findsOneWidget);
  });
  testWidgets('invalid credentials stay local with accessible field errors', (tester) async {
    var requests = 0;
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((_) async { requests++; return http.Response('{}', 500); }));
    await tester.pumpWidget(app(AccountScreen(origin: session.origin, session: session)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle();
    expect(find.text('Введите имя из 3–40 допустимых символов'), findsOneWidget);
    expect(find.text('Пароль должен содержать 12–256 символов'), findsOneWidget);
    expect(requests, 0);
    session.close();
  });

}
