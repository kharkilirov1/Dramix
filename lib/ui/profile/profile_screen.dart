import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/net.dart';
import '../../core/premium.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../account/account_screen.dart';
import '../premium/paywall_screen.dart';
import '../release/title_screen.dart';
import '../root.dart';
import '../widgets.dart';

/// Local library overview; server accounts remain optional and separate.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  LibraryStats? _stats;
  bool _failed = false;
  int _loadVersion = 0;

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

  void _onLibraryChanged() { if (mounted) _load(); }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() => _failed = false);
    try {
      final stats = await Library.stats();
      if (mounted && version == _loadVersion) setState(() => _stats = stats);
    } catch (_) {
      if (mounted && version == _loadVersion) setState(() => _failed = true);
    }
  }

  Future<void> _settings() async {
    await Navigator.pushNamed(context, Routes.settings);
    if (mounted) setState(() {});
  }

  void _openList(WatchStatus status) => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => _ProfileListScreen(status: status)),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          TopBar(searchHint: 'Поиск дорам',
              onSearch: () => Navigator.pushNamed(context, Routes.search)),
          if (_failed)
            ErrorCentered(message: 'Не удалось прочитать локальную библиотеку.', onRetry: _load)
          else if (_stats == null)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _content(_stats!),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  Widget _content(LibraryStats stats) {
    final listTotal = stats.listCounts.values.fold<int>(0, (sum, value) => sum + value);
    final origin = Net.backendOrigin;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.person_outline, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            const Text('Моя библиотека',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('История, избранное и списки на этом устройстве. '
                'Для просмотра аккаунт не нужен.',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth < 360
                  ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;
              return Wrap(spacing: 12, runSpacing: 12, children: [
                _counter(stats.historySize, 'Точек в истории', width),
                _counter(stats.favorites, 'В избранном', width),
                _counter(listTotal, 'В списках', width),
              ]);
            }),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Аккаунт и облако',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(origin == null
                ? 'Сервер не подключён. Вся библиотека доступна локально.'
                : 'Дополнительный сервер настроен. Вход и копирование библиотеки '
                  'выполняются отдельно; локальные данные остаются на устройстве.'),
            const SizedBox(height: 12),
            if (origin != null) OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push<void>(context, MaterialPageRoute(
                    builder: (_) => AccountScreen(origin: origin)));
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Открыть аккаунт сервера'),
            ),
            TextButton.icon(
              onPressed: _settings,
              icon: const Icon(Icons.settings_outlined),
              label: Text(origin == null ? 'Настроить сервер и приложение' : 'Настройки приложения'),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        color: AppColors.surface,
        child: ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(Premium.isPremium ? 'Dramix Plus активен' : 'Dramix Plus'),
          subtitle: Text(Premium.isPremium
              ? (Premium.isLifetime ? 'Без продления' : 'Осталось дней: ${Premium.daysLeft ?? 0}')
              : 'Возможности и условия'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async { await ensurePremium(context); },
        ),
      ),
      const SizedBox(height: 20),
      const Text('Мои списки', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (listTotal == 0) const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Списки пока пусты. Добавьте дораму в список на её странице.',
            style: TextStyle(color: AppColors.textSecondary)),
      ),
      for (var i = 0; i < WatchStatus.values.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: AppColors.surface,
          child: ListTile(
            leading: ExcludeSemantics(child: Icon(Icons.circle, size: 12, color: _statusColors[i])),
            title: Text(WatchStatus.values[i].title),
            subtitle: Text('Дорам: ${stats.countFor(WatchStatus.values[i])}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openList(WatchStatus.values[i]),
          ),
        ),
      const SizedBox(height: 20),
      const Text('Распределение списков',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      if (listTotal > 0) LayoutBuilder(builder: (context, constraints) {
        final chart = ExcludeSemantics(
          child: SizedBox(
            width: 180, height: 180,
            child: PieChart(PieChartData(
              sectionsSpace: 2, centerSpaceRadius: 36, sections: _sections(stats),
            )),
          ),
        );
        final legend = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < WatchStatus.values.length; i++) Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('${WatchStatus.values[i].title}: '
                '${stats.countFor(WatchStatus.values[i])}'),
          ),
        ]);
        if (constraints.maxWidth >= 540 &&
            MediaQuery.textScalerOf(context).scale(16) <= 24) {
          return Row(children: [Expanded(child: legend), const SizedBox(width: 24), chart]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: chart), const SizedBox(height: 12), legend,
        ]);
      }) else const Text('Диаграмма появится после добавления дорам в списки.',
          style: TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      const Text('История хранит точки продолжения, а не подтверждение завершения '
          'серии. Сумма сохранённых позиций не равна времени просмотра.',
          style: TextStyle(color: AppColors.textSecondary)),
    ]);
  }

  static const _statusColors = <Color>[
    AppColors.statWatching, AppColors.statPlans, AppColors.statCompleted,
    AppColors.statHoldOn, AppColors.statDropped,
  ];

  List<PieChartSectionData> _sections(LibraryStats stats) => [
    for (var i = 0; i < WatchStatus.values.length; i++)
      if (stats.countFor(WatchStatus.values[i]) > 0)
        PieChartSectionData(
          value: stats.countFor(WatchStatus.values[i]).toDouble(),
          color: _statusColors[i], radius: 28, showTitle: false,
        ),
  ];

  Widget _counter(int value, String label, double width) => Semantics(
    label: '$label: $value',
    child: ExcludeSemantics(child: SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
      ),
    )),
  );
}

class _ProfileListScreen extends StatefulWidget {
  final WatchStatus status;
  const _ProfileListScreen({required this.status});
  @override
  State<_ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends State<_ProfileListScreen> {
  late Future<List<SavedTitleRef>> _items;
  @override
  void initState() {
    super.initState();
    _items = Library.list(widget.status);
    Library.revision.addListener(_reload);
  }
  void _reload() {
    if (mounted) setState(() => _items = Library.list(widget.status));
  }
  @override
  void dispose() {
    Library.revision.removeListener(_reload);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => PageScaffold(
    title: widget.status.title,
    body: FutureBuilder<List<SavedTitleRef>>(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.hasError) return ErrorCentered(
            message: 'Не удалось прочитать список.', onRetry: _reload);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return SavedList(
          items: snapshot.data!,
          emptyText: 'В этом списке пока нет дорам',
          onTap: (context, title) => openSavedTitle(context, title),
        );
      },
    ),
  );
}
