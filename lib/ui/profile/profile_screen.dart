import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/premium.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../premium/paywall_screen.dart';
import '../root.dart';
import '../widgets.dart';

/// Профиль: эталонная вёрстка, но с локальными числами.
///
/// Kodik has no accounts at all, so everything here comes from [Library] on the
/// device — there is nothing to fetch and nothing to log into.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  LibraryStats? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    Library.revision.addListener(_onLibraryChanged);
    Premium.revision.addListener(_onLibraryChanged);
    _load();
  }

  @override
  void dispose() {
    Library.revision.removeListener(_onLibraryChanged);
    Premium.revision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final stats = await Library.stats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return SafeArea(
      bottom: false,
      child: ListView(children: [
        TopBar(
          searchHint: 'Поиск дорам',
          onSearch: () => Navigator.pushNamed(context, Routes.search),
        ),
        if (_error != null)
          ErrorCentered(message: _error!, onRetry: _load)
        else if (stats == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child:
                Center(child: CircularProgressIndicator(color: AppColors.textSecondary)),
          )
        else
          _content(stats),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _content(LibraryStats stats) {
    final listTotal =
        stats.listCounts.values.fold<int>(0, (sum, value) => sum + value);
    final sections = _sections(stats);
    return Column(children: [
      const SizedBox(height: 16),
      Container(
        width: 110,
        height: 110,
        decoration: const BoxDecoration(
            color: Colors.white, shape: BoxShape.circle),
        child: const Center(
          child: Icon(Icons.person_outline,
              size: 54, color: AppColors.textTertiary),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Мой профиль',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Вы смотрите дорамы на этом устройстве',
          style: TextStyle(fontSize: 14.5, color: AppColors.textSecondary)),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _counter(stats.watchedEpisodes, 'серий'),
        _counter(stats.favorites, 'избранное'),
        _counter(listTotal, 'в списках'),
        _counter(stats.historySize, 'в истории'),
      ]),
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        // Material is provided here rather than assumed from an ancestor: the
        // ink splash needs one, and this card must render standalone too.
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              await ensurePremium(context);
            },
            child: Ink(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: Premium.isPremium
                      ? const [Color(0xFF3A2E52), Color(0xFF4A4458)]
                      : const [Color(0xFF2A2A33), Color(0xFF3A3A45)],
                ),
              ),
              child: Row(children: [
                Icon(
                  Premium.isPremium
                      ? Icons.verified_rounded
                      : Icons.workspace_premium_rounded,
                  color:
                      Premium.isPremium ? Colors.white : AppColors.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Premium.isPremium ? 'Dramix Plus активен' : 'Dramix Plus',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        Premium.isPremium
                            ? (Premium.isLifetime
                                ? 'Навсегда, без продления'
                                : 'Осталось дней: ${Premium.daysLeft ?? 0}')
                            : 'Фильтры, история и подборки без ограничений',
                        style: const TextStyle(
                            fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textTertiary, size: 20),
              ]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pushNamed(context, Routes.settings),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.outline),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                padding: const EdgeInsets.symmetric(vertical: 13)),
            child: const Text('Настройки',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
      const SizedBox(height: 26),
      const Divider(color: AppColors.outline, height: 1),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(children: [
          Text('Статистика',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          SizedBox(width: 8),
          Icon(Icons.info_outline, size: 18, color: AppColors.textTertiary),
          Spacer(),
          Text('Показать все',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ]),
      ),
      SizedBox(
        height: 190,
        child: Row(children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < WatchStatus.values.length; i++)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                    child: Row(children: [
                      Container(
                          width: 14,
                          height: 14,
                          color: _statusColors[i]),
                      const SizedBox(width: 10),
                      Text(WatchStatus.values[i].title,
                          style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 8),
                      Text('${stats.countFor(WatchStatus.values[i])}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: PieChart(PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              sections: sections,
            )),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Просмотрено серий:  ${stats.watchedEpisodes}',
              style: const TextStyle(
                  fontSize: 14.5, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('Время просмотра:  ~ ${stats.watchedDays} дн.',
              style: const TextStyle(
                  fontSize: 14.5, color: AppColors.textSecondary)),
        ]),
      ),
      const SizedBox(height: 18),
      const Divider(color: AppColors.outline, height: 1),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(children: [
          Text('Мои списки',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        ]),
      ),
      for (var i = 0; i < WatchStatus.values.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(children: [
            Container(width: 10, height: 10, color: _statusColors[i]),
            const SizedBox(width: 10),
            Text(WatchStatus.values[i].title,
                style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
            Text('${stats.countFor(WatchStatus.values[i])}',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
    ]);
  }

  /// Slice colours in [WatchStatus.values] order.
  static const List<Color> _statusColors = <Color>[
    AppColors.statWatching,
    AppColors.statPlans,
    AppColors.statCompleted,
    AppColors.statHoldOn,
    AppColors.statDropped,
  ];

  /// One slice per non-empty list; a flat ring keeps the chart readable when
  /// the device has no watch data yet.
  List<PieChartSectionData> _sections(LibraryStats stats) {
    final out = <PieChartSectionData>[];
    for (var i = 0; i < WatchStatus.values.length; i++) {
      final count = stats.countFor(WatchStatus.values[i]);
      if (count <= 0) continue;
      out.add(PieChartSectionData(
          value: count.toDouble(),
          color: _statusColors[i],
          radius: 34,
          showTitle: false));
    }
    if (out.isEmpty) {
      out.add(PieChartSectionData(
          value: 1,
          color: AppColors.surface,
          radius: 34,
          showTitle: false));
    }
    return out;
  }

  Widget _counter(int value, String label) {
    return Column(children: [
      Text('$value',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
    ]);
  }
}
