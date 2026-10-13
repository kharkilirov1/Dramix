import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/widgets.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: child),
    );

Widget _row(BuildContext context, KodikTitle title, int index) => SizedBox(
      height: 100,
      child: Text(title.title),
    );

KodikTitle _title(int index) => KodikTitle(
      id: '$index',
      type: 'foreign-serial',
      title: 'Строка $index',
    );

void main() {
  group('PagedScroll recovery', () {
    testWidgets('shows an initial error and retries the first page',
        (tester) async {
      final cursors = <String?>[];
      await tester.pumpWidget(_host(PagedScroll(
        loader: (cursor) async {
          cursors.add(cursor);
          if (cursors.length == 1) throw StateError('initial failure');
          return KodikPage(total: 1, results: [_title(0)]);
        },
        itemBuilder: _row,
      )));
      await tester.pump();

      expect(find.textContaining('initial failure'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(cursors, <String?>[null]);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      await tester.pump();

      expect(cursors, <String?>[null, null]);
      expect(find.text('Строка 0'), findsOneWidget);
      expect(find.textContaining('initial failure'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('keeps loaded rows and retries the failed next-page cursor',
        (tester) async {
      final cursors = <String?>[];
      final nextPage = Completer<KodikPage>();
      await tester.pumpWidget(_host(PagedScroll(
        loader: (cursor) {
          cursors.add(cursor);
          if (cursor == null) {
            return Future.value(KodikPage(
              total: 11,
              results: List.generate(10, _title),
              nextPage: 'page-2',
            ));
          }
          if (cursors.length == 2) return nextPage.future;
          return Future.value(KodikPage(total: 11, results: [_title(10)]));
        },
        itemBuilder: _row,
      )));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pump();

      expect(cursors, <String?>[null, 'page-2']);
      nextPage.completeError(StateError('next-page failure'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Строка 9'), findsOneWidget);
      expect(find.textContaining('next-page failure'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      await tester.pump();

      expect(cursors, <String?>[null, 'page-2', 'page-2']);
      expect(find.text('Строка 9'), findsOneWidget);
      expect(find.textContaining('next-page failure'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(find.text('Строка 10'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('retries a filtered-out page cursor without resetting its budget',
        (tester) async {
      final cursors = <String?>[];
      var failed = false;
      await tester.pumpWidget(_host(PagedScroll(
        loader: (cursor) async {
          cursors.add(cursor);
          if (cursor == 'page-2' && !failed) {
            failed = true;
            throw StateError('filtered next-page failure');
          }
          final page = cursor == null ? 1 : int.parse(cursor.split('-').last);
          return KodikPage(
            total: 8,
            results: [_title(page)],
            nextPage: page < 8 ? 'page-${page + 1}' : null,
          );
        },
        accept: (title) => title.id == '8',
        itemBuilder: _row,
      )));
      await tester.pump();
      await tester.pump();

      expect(cursors, <String?>[null, 'page-2']);
      expect(find.textContaining('filtered next-page failure'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Повторить'));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      expect(cursors, <String?>[
        null,
        'page-2',
        'page-2',
        'page-3',
        'page-4',
        'page-5',
        'page-6',
        'page-7',
      ]);
      expect(find.text('Загрузить ещё'), findsOneWidget);
      expect(find.text('Строка 8'), findsNothing);
      expect(find.textContaining('filtered next-page failure'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Загрузить ещё'));
      await tester.pump();
      await tester.pump();

      expect(cursors.last, 'page-8');
      expect(cursors.length, 9);
      expect(find.text('Строка 8'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('offers manual continuation after empty filtered-page budget',
        (tester) async {
      final cursors = <String?>[];
      await tester.pumpWidget(_host(PagedScroll(
        loader: (cursor) async {
          cursors.add(cursor);
          final page = cursors.length;
          return KodikPage(
            total: 8,
            results: [_title(page)],
            nextPage: page < 8 ? 'page-${page + 1}' : null,
          );
        },
        accept: (title) => title.id == '8',
        itemBuilder: _row,
      )));
      // Bounded pumps also detect the old permanently spinning state without
      // waiting for pumpAndSettle's timeout.
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      expect(cursors, <String?>[
        null,
        'page-2',
        'page-3',
        'page-4',
        'page-5',
        'page-6',
        'page-7',
      ]);
      expect(find.text('Загрузить ещё'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Загрузить ещё'));
      await tester.pump();
      await tester.pump();

      expect(cursors.last, 'page-8');
      expect(cursors.length, 8);
      expect(find.text('Строка 8'), findsOneWidget);
      expect(find.text('Загрузить ещё'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
