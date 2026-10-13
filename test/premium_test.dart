import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/models.dart';
import 'package:dramix/core/premium.dart';
import 'package:dramix/core/storage.dart';

class _FakeGateway implements PurchaseGateway {
  @override
  Future<bool> buy(PremiumPlan plan) async => true;

  @override
  Future<bool> restore() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Premium.gateway = const UnavailablePurchaseGateway();
    await Premium.revoke();
  });

  group('unlock codes', () {
    test('accepts a code the operator would issue', () async {
      final code = Premium.codeFor(365);

      expect(await Premium.unlockWithCode(code), isTrue);
      expect(Premium.isPremium, isTrue);
      expect(Premium.daysLeft, greaterThan(360));
    });

    test('is tolerant of case and surrounding spaces', () async {
      final code = Premium.codeFor(30).toLowerCase();
      expect(await Premium.unlockWithCode('  $code  '), isTrue);
    });

    test('rejects a code with a tampered duration', () async {
      final parts = Premium.codeFor(30).split('-');
      final forged = 'DRMX-365-${parts[2]}';

      expect(await Premium.unlockWithCode(forged), isFalse);
      expect(Premium.isPremium, isFalse);
    });

    test('rejects malformed input', () async {
      const bad = <String>[
        '',
        'DRMX',
        'DRMX-30',
        'XXXX-30-ABCDEF',
        'DRMX-0-000000',
        'DRMX-abc-000000',
        'DRMX-99999-000000',
      ];
      for (final code in bad) {
        expect(await Premium.unlockWithCode(code), isFalse, reason: code);
      }
      expect(Premium.isPremium, isFalse);
    });

    test('extends an active subscription instead of replacing it', () async {
      await Premium.unlockWithCode(Premium.codeFor(30));
      final afterFirst = Premium.daysLeft!;

      await Premium.unlockWithCode(Premium.codeFor(30));

      expect(Premium.daysLeft!, greaterThan(afterFirst));
    });

    test('checksum is stable for the same duration', () {
      expect(Premium.checksum(30), Premium.checksum(30));
      expect(Premium.checksum(30), isNot(Premium.checksum(31)));
      expect(Premium.codeFor(30).split('-').last, hasLength(6));
    });
  });

  group('trial', () {
    test('can be taken exactly once', () async {
      expect(await Premium.trialUsed(), isFalse);

      expect(await Premium.startTrial(), isTrue);
      expect(Premium.isPremium, isTrue);
      expect(await Premium.trialUsed(), isTrue);

      // Compare the entitlement itself: the rounded display can change while
      // this async test crosses a wall-clock boundary.
      final until = Premium.until;
      expect(await Premium.startTrial(), isFalse);
      expect(Premium.until, until);
    });
  });

  group('entitlement lifecycle', () {
    test('a lifetime grant never expires', () async {
      await Premium.grant(PremiumTier.plus);

      expect(Premium.isPremium, isTrue);
      expect(Premium.isLifetime, isTrue);
      expect(Premium.daysLeft, isNull);
    });

    test('an elapsed subscription stops being premium', () async {
      await Premium.grant(PremiumTier.plus,
          until: DateTime.now().subtract(const Duration(days: 1)));

      expect(Premium.isPremium, isFalse);
      expect(Premium.tier, PremiumTier.plus,
          reason: 'the tier is stored; expiry is what shuts it off');
    });

    test('survives a reload from disk', () async {
      await Premium.unlockWithCode(Premium.codeFor(10));

      await Premium.load();

      expect(Premium.isPremium, isTrue);
      expect(Premium.daysLeft, greaterThan(8));
    });

    test('revoke clears the entitlement', () async {
      await Premium.grant(PremiumTier.plus);
      await Premium.revoke();

      expect(Premium.isPremium, isFalse);
      expect(Premium.tier, PremiumTier.free);
    });
  });

  group('purchase gateway', () {
    test('buying fails while no billing is connected', () async {
      expect(await Premium.buy(PremiumPlan.year), isFalse);
      expect(Premium.isPremium, isFalse);
    });

    test('a connected gateway grants the plan duration', () async {
      Premium.gateway = _FakeGateway();

      expect(await Premium.buy(PremiumPlan.month), isTrue);
      expect(Premium.isPremium, isTrue);
      expect(Premium.daysLeft, greaterThan(28));
    });
  });

  group('history quota follows the tier', () {
    Future<void> record(int count, {int from = 0}) async {
      for (var i = from; i < from + count; i++) {
        await Library.record(WatchEntry(
          title: SavedTitleRef(id: 'serial-$i', title: 'Тайтл $i'),
          episode: i,
          watchedAt: DateTime(2024, 1, 1).add(Duration(minutes: i)),
        ));
      }
    }

    test('free tier keeps a short tail, Plus keeps more', () async {
      await record(40);
      expect((await Library.history()).length, Library.freeHistory);

      await Premium.grant(PremiumTier.plus);
      await record(30, from: 40);

      final length = (await Library.history()).length;
      expect(length, greaterThan(Library.freeHistory));
      expect(length, lessThanOrEqualTo(Library.maxHistory));
    });
  });
}
