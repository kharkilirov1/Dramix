import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/premium.dart';
import '../../core/theme.dart';
import '../widgets.dart';

/// Opens the paywall and reports whether the user is premium afterwards.
Future<bool> ensurePremium(BuildContext context, {String? reason}) async {
  if (Premium.isPremium) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PaywallScreen(reason: reason)),
  );
  return Premium.isPremium;
}

/// Dramix Plus — the paid tier.
///
/// Billing is not connected in this build ([Premium.gateway] is the seam), so
/// the purchase buttons say so plainly rather than faking a checkout. The trial
/// and unlock codes work for real.
class PaywallScreen extends StatefulWidget {
  /// Shown when the paywall was opened by a locked feature.
  final String? reason;

  const PaywallScreen({super.key, this.reason});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PremiumPlan _plan = PremiumPlan.year;
  bool _busy = false;
  bool _trialUsed = true;

  static const List<(IconData, String, String)> _features = [
    (
      Icons.tune,
      'Расширенные фильтры',
      'Страна, жанры, минимальный рейтинг, возраст и «скрыть просмотренное»'
    ),
    (
      Icons.history,
      'Полная история',
      'До 200 записей вместо 30 — фильмография не теряется'
    ),
    (
      Icons.bookmarks_outlined,
      'Подборки Plus',
      'Закрытые коллекции: новинки по странам и жанровые подборки'
    ),
    (
      Icons.block,
      'Без рекламных баннеров',
      'Внутренние промо-блоки приложения скрыты'
    ),
    (
      Icons.sync_alt,
      'Перенос списков',
      'Экспорт истории и избранного в файл'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadTrial();
  }

  Future<void> _loadTrial() async {
    final used = await Premium.trialUsed();
    if (mounted) setState(() => _trialUsed = used);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _buy() async {
    setState(() => _busy = true);
    final ok = await Premium.buy(_plan);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok
        ? 'Активировано: ${_plan.label}'
        : 'Оплата пока не подключена. Используйте пробный период или код активации.');
  }

  Future<void> _trial() async {
    final ok = await Premium.startTrial();
    if (!mounted) return;
    setState(() => _trialUsed = true);
    if (ok) {
      _snack('Пробный период на 3 дня активирован');
      Navigator.of(context).maybePop();
    } else {
      _snack('Пробный период уже использован');
    }
  }

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Код активации'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 15, letterSpacing: 1.2),
          decoration: const InputDecoration(hintText: 'DRMX-365-XXXXXX'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Активировать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty) return;
    final ok = await Premium.unlockWithCode(code);
    if (!mounted) return;
    if (ok) {
      _snack('Plus активирован');
      Navigator.of(context).maybePop();
    } else {
      HapticFeedback.vibrate();
      _snack('Код не подошёл');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final ok = await Premium.restore();
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(ok ? 'Покупки восстановлены' : 'Покупок для восстановления нет');
  }

  /// Release builds hide this; it exists so the flow can be exercised locally.
  Future<void> _debugReset() async {
    await Premium.revoke();
    if (!mounted) return;
    setState(() {});
    _snack('Подписка сброшена (отладка)');
  }

  @override
  Widget build(BuildContext context) {
    final premium = Premium.isPremium;
    return PageScaffold(
      title: 'Dramix Plus',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _hero(premium),
          if (widget.reason != null && !premium) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 18, color: AppColors.statHoldOn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.reason!,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 22),
          const Text('Что входит',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final feature in _features) _featureRow(feature),
          const SizedBox(height: 24),
          const Text('Тариф',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final plan in PremiumPlan.values) _planCard(plan),
          const SizedBox(height: 18),
          LightPillButton(
            label: premium ? 'Подписка активна' : 'Оформить ${_plan.label}',
            loading: _busy,
            onTap: premium ? null : _buy,
          ),
          if (!premium) ...[
            const SizedBox(height: 8),
            const Text(
              'Приём платежей в этой сборке не подключён: нужен биллинг магазина '
              'или собственный шлюз. Кнопка честно сообщает об этом и ничего не '
              'списывает.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (!_trialUsed)
              OutlinedButton(
                onPressed: _trial,
                style: _outlineStyle,
                child: const Text('Пробный период 3 дня',
                    style: TextStyle(fontSize: 15.5)),
              ),
            if (!_trialUsed) const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _enterCode,
              style: _outlineStyle,
              child: const Text('У меня есть код', style: TextStyle(fontSize: 15.5)),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : _restore,
              style: _outlineStyle,
              child: const Text('Восстановить покупки',
                  style: TextStyle(fontSize: 15.5)),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                Premium.isLifetime
                    ? 'Навсегда, без продления'
                    : 'Осталось дней: ${Premium.daysLeft ?? 0}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: _debugReset,
                child: const Text('Сбросить подписку (отладка)',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static final ButtonStyle _outlineStyle = OutlinedButton.styleFrom(
    side: const BorderSide(color: AppColors.outline),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    padding: const EdgeInsets.symmetric(vertical: 14),
    foregroundColor: AppColors.textPrimary,
  );

  Widget _hero(bool premium) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2E52), Color(0xFF4A4458)],
        ),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(premium ? Icons.verified_rounded : Icons.workspace_premium_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(premium ? 'Plus активен' : 'Dramix Plus',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                premium
                    ? 'Все возможности открыты'
                    : 'Фильтры, история и подборки без ограничений',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _featureRow((IconData, String, String) feature) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle_rounded,
            size: 20, color: AppColors.statWatching),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(feature.$2,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(feature.$3,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppColors.textTertiary, height: 1.35)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _planCard(PremiumPlan plan) {
    final active = plan == _plan;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => setState(() => _plan = plan),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: active ? AppColors.statPlans : AppColors.outline,
                width: active ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(
              active
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: active ? AppColors.statPlans : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(plan.label,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(plan.description,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textTertiary)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
