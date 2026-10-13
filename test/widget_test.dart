import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/widgets.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: child),
    );

void main() {
  group('ReleaseListItem', () {
    testWidgets('renders title, meta line and rating', (tester) async {
      await tester.pumpWidget(_host(ReleaseListItem(
        title: 'Винченцо',
        meta: '20 из 20 эп.',
        grade: 8.4,
        description: 'Корейская дорама про мафию',
        onTap: () {},
      )));

      expect(find.text('Винченцо'), findsOneWidget);
      expect(find.text('20 из 20 эп.'), findsOneWidget);
      expect(find.text('8.4'), findsOneWidget);
      expect(find.text('Корейская дорама про мафию'), findsOneWidget);
    });

    testWidgets('omits the rating when there is none', (tester) async {
      await tester.pumpWidget(_host(const ReleaseListItem(
        title: 'Без рейтинга',
        meta: 'Фильм',
      )));

      expect(find.text('Без рейтинга'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });

    testWidgets('shows a rank gutter only when ranked', (tester) async {
      await tester.pumpWidget(_host(const ReleaseListItem(
        title: 'Первое место',
        meta: '16 эп.',
        rank: 1,
      )));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('Первое место'), findsOneWidget);
    });

    testWidgets('strips HTML from the description', (tester) async {
      await tester.pumpWidget(_host(const ReleaseListItem(
        title: 'HTML',
        meta: '1 эп.',
        description: 'Строка<br>с тегами',
      )));

      expect(find.textContaining('<br>'), findsNothing);
      expect(find.textContaining('Строка'), findsOneWidget);
    });

    testWidgets('fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(ReleaseListItem(
        title: 'Нажми меня',
        meta: '8 эп.',
        onTap: () => tapped = true,
      )));

      await tester.tap(find.text('Нажми меня'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('UnderlineTabs', () {
    testWidgets('renders every tab and reports selection', (tester) async {
      var selected = -1;
      await tester.pumpWidget(_host(UnderlineTabs(
        tabs: const ['Моя вкладка', 'Последнее', 'Онгоинги'],
        selected: 1,
        onChanged: (i) => selected = i,
      )));

      expect(find.text('Моя вкладка'), findsOneWidget);
      expect(find.text('Последнее'), findsOneWidget);
      expect(find.text('Онгоинги'), findsOneWidget);

      await tester.tap(find.text('Онгоинги'));
      await tester.pump();
      expect(selected, 2);
    });
  });

  group('LightPillButton', () {
    testWidgets('fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(LightPillButton(
        label: 'Применить',
        onTap: () => tapped = true,
      )));

      await tester.tap(find.text('Применить'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('swaps the label for a spinner while loading', (tester) async {
      await tester.pumpWidget(_host(const LightPillButton(
        label: 'Применить',
        loading: true,
      )));

      expect(find.text('Применить'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ErrorCentered', () {
    testWidgets('shows the message and fires retry', (tester) async {
      var retried = false;
      await tester.pumpWidget(_host(ErrorCentered(
        message: 'Сеть недоступна',
        onRetry: () => retried = true,
      )));

      expect(find.text('Сеть недоступна'), findsOneWidget);
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('omits retry without a handler', (tester) async {
      await tester.pumpWidget(_host(const ErrorCentered(message: 'Пусто')));

      expect(find.text('Пусто'), findsOneWidget);
      expect(find.text('Повторить'), findsNothing);
    });
  });

  group('stripHtml', () {
    test('removes markup and collapses the gap it leaves', () {
      expect(stripHtml('Строка<br>с тегами'), 'Строка с тегами');
      expect(stripHtml('<b>Жирный</b> текст'), ' Жирный текст');
      expect(stripHtml('без тегов'), 'без тегов');
    });
  });
}
