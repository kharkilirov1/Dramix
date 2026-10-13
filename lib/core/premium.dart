import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user has unlocked.
enum PremiumTier {
  free('Бесплатно'),
  plus('Dramix Plus');

  const PremiumTier(this.label);

  final String label;
}

/// A purchasable plan shown on the paywall.
enum PremiumPlan {
  month('Месяц', 30, 'Подписка, продлевается вручную'),
  year('Год', 365, 'Выгоднее месяца примерно втрое'),
  lifetime('Навсегда', null, 'Разовая покупка, без продления');

  const PremiumPlan(this.label, this.days, this.description);

  final String label;

  /// `null` means the unlock never expires.
  final int? days;
  final String description;
}

/// Store billing is not wired up in this build, so [Premium.gateway] is a seam
/// rather than a live integration: plug an `in_app_purchase` (or RuStore /
/// Yandex) implementation in here and the paywall starts working unchanged.
abstract class PurchaseGateway {
  Future<bool> buy(PremiumPlan plan);
  Future<bool> restore();
}

/// Default gateway. Purchases report failure instead of pretending to succeed;
/// the trial and unlock codes below are fully functional without it.
class UnavailablePurchaseGateway implements PurchaseGateway {
  const UnavailablePurchaseGateway();

  @override
  Future<bool> buy(PremiumPlan plan) async => false;

  @override
  Future<bool> restore() async => false;
}

/// Entitlement state for the paid tier.
///
/// Everything is stored on device — Kodik has no accounts and this build has no
/// backend. That has a direct consequence for unlock codes, see
/// `docs/MONETIZATION.md`: the check below is deliberately simple and a
/// determined user can forge it. A shipping product must verify codes on a
/// server.
class Premium {
  const Premium._();

  static const String _key = 'dramix.premium';
  static const String _trialKey = 'dramix.premium.trial';
  static const String _codeSalt = 'dramix-code-v1';

  /// Bumped on any entitlement change so open screens can re-render.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Swapped for a real billing implementation.
  static PurchaseGateway gateway = const UnavailablePurchaseGateway();

  static PremiumTier _tier = PremiumTier.free;
  static DateTime? _until;

  static PremiumTier get tier => _tier;
  static DateTime? get until => _until;

  /// True while the paid tier is active (a lifetime unlock has no expiry).
  static bool get isPremium =>
      _tier == PremiumTier.plus && (_until == null || _until!.isAfter(DateTime.now()));

  static bool get isLifetime => _until == null && _tier == PremiumTier.plus;

  /// Whole days left, or `null` for lifetime / free.
  static int? get daysLeft {
    final until = _until;
    if (!isPremium || until == null) return null;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? 0 : diff.inDays + 1;
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apply(prefs.getString(_key));
  }

  /// Grants a tier locally. Called by the gateway, by the trial and by codes.
  static Future<void> grant(PremiumTier tier, {DateTime? until}) async {
    _tier = tier;
    _until = tier == PremiumTier.plus ? until : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(<String, dynamic>{
        'tier': _tier.name,
        if (_until != null) 'until': _until!.toIso8601String(),
      }),
    );
    revision.value++;
  }

  static Future<void> revoke() => grant(PremiumTier.free);

  static Future<bool> buy(PremiumPlan plan) async {
    final ok = await gateway.buy(plan);
    if (!ok) return false;
    await grant(PremiumTier.plus,
        until: plan.days == null
            ? null
            : DateTime.now().add(Duration(days: plan.days!)));
    return true;
  }

  static Future<bool> restore() async {
    if (!await gateway.restore()) return false;
    revision.value++;
    return true;
  }

  // ------------------------------------------------------------------ trial

  static Future<bool> trialUsed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_trialKey) == true;
  }

  /// One-off 3-day trial. Real: it is granted locally and remembered, so it can
  /// only be taken once per install.
  static Future<bool> startTrial({int days = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_trialKey) == true) return false;
    await prefs.setBool(_trialKey, true);
    await grant(PremiumTier.plus,
        until: DateTime.now().add(Duration(days: days)));
    return true;
  }

  // ------------------------------------------------------------------- codes

  /// Deterministic check digit for a code of `days` length.
  ///
  /// FNV-1a over `salt + days`; cheap and dependency-free. Not a security
  /// boundary — see the class comment.
  static String checksum(int days) {
    var hash = 0x811c9dc5;
    for (final unit in '$_codeSalt:$days'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).toUpperCase().padLeft(8, '0').substring(0, 6);
  }

  /// Builds the code that [unlockWithCode] accepts. Operators generate codes
  /// with this; tests rely on it too.
  static String codeFor(int days) => 'DRMX-$days-${checksum(days)}';

  /// Redeems an unlock code, e.g. `DRMX-365-1A2B3C`.
  static Future<bool> unlockWithCode(String raw) async {
    final code = raw.trim().toUpperCase().replaceAll(' ', '');
    final parts = code.split('-');
    if (parts.length != 3 || parts[0] != 'DRMX') return false;
    final days = int.tryParse(parts[1]);
    if (days == null || days <= 0 || days > 3650) return false;
    if (parts[2] != checksum(days)) return false;

    // Codes extend an active subscription instead of replacing it.
    final base = isPremium && _until != null && _until!.isAfter(DateTime.now())
        ? _until!
        : DateTime.now();
    await grant(PremiumTier.plus, until: base.add(Duration(days: days)));
    return true;
  }

  static void _apply(String? raw) {
    if (raw == null || raw.isEmpty) {
      _tier = PremiumTier.free;
      _until = null;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _tier = PremiumTier.free;
        _until = null;
        return;
      }
      _tier = decoded['tier'] == PremiumTier.plus.name
          ? PremiumTier.plus
          : PremiumTier.free;
      _until = DateTime.tryParse((decoded['until'] as String?) ?? '');
    } catch (_) {
      _tier = PremiumTier.free;
      _until = null;
    }
  }
}
