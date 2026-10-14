import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// A finite recent-update sample grouped by the local weekday of updatedAt.
/// This is not an airing calendar or proof that an episode was released.
class ScheduleScreen extends StatefulWidget {
  final Future<KodikPage> Function()? loader;

  const ScheduleScreen({super.key, this.loader});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  /// 1 = Пн … 7 = Вс, matching `DateTime.weekday`.
  static const List<String> _dayTabs = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  int _day = DateTime.now().weekday;
  bool _selectedByUser = false;
  bool _loading = true;
  String? _error;

  /// Weekday → titles, only for weekdays that actually had updates.
  final Map<int, List<KodikTitle>> _byDay = <int, List<KodikTitle>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await (widget.loader?.call() ?? KodikApi.instance.browseFiltered(
        CatalogFilter(types: KodikCatalog.all, sort: CatalogSort.updated),
        limit: 50,
      ));
      if (!mounted) return;
      final grouped = <int, List<KodikTitle>>{};
      for (final title in KodikApi.dedupe(page.results)) {
        final weekday = title.updatedAt?.toLocal().weekday;
        if (weekday == null) continue;
        grouped.putIfAbsent(weekday, () => <KodikTitle>[]).add(title);
      }
      final dated = grouped.values.expand((titles) => titles).toList()
        ..sort((a, b) => b.updatedAt!.compareTo(a.updatedAt!));
      setState(() {
        if (!_selectedByUser && !grouped.containsKey(_day) && dated.isNotEmpty) {
          _day = dated.first.updatedAt!.toLocal().weekday;
        }
        _byDay
          ..clear()
          ..addAll(grouped);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить обновления. Проверьте подключение и повторите попытку.';
        _loading = false;
      });
    }
  }

  int get _totalTitles =>
      _byDay.values.fold<int>(0, (sum, items) => sum + items.length);

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.textSecondary),
      );
    }
    if (_error != null) {
      return ErrorCentered(message: _error!, onRetry: _load);
    }
    final titles = _byDay[_day] ?? const <KodikTitle>[];
    if (_totalTitles == 0 || titles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _totalTitles == 0
                ? 'В загруженной выборке нет обновлений с указанной датой'
                : 'В загруженной выборке нет обновлений за этот день недели',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textTertiary),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: titles.length,
      itemBuilder: (context, index) {
        final title = titles[index];
        return ReleaseListItem.kodik(
          title,
          onTap: () => openTitle(context, title),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'По дням',
      actions: [IconButton(
        tooltip: 'Обновить выборку',
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
      )],
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Последние обновления каталога по дням недели. '
                'Выборка до 50 записей; это не расписание выхода серий.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textTertiary),
              ),
            ),
          ),
          UnderlineTabs(
            tabs: _dayTabs,
            selected: _day - 1,
            onChanged: (i) => setState(() {
              _day = i + 1;
              _selectedByUser = true;
            }),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
