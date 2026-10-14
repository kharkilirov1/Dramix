import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dramix/core/premium.dart';
import 'package:dramix/core/theme.dart';
import 'package:dramix/ui/filter/filter_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Premium.grant(PremiumTier.plus);
  });
  tearDown(() => Premium.grant(PremiumTier.free));

  for (final label in ['Страна', 'Жанры']) {
    testWidgets('$label opens multi-select immediately', (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(), home: const FilterScreen()));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsWidgets);
      expect(find.text('Готово'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Неважно'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
