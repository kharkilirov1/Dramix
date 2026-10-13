import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Расписание: Kodik has no airing calendar, so the reference Пн–Вс tabs show
/// the recently updated feed grouped by the weekday of `KodikTitle.updatedAt`.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  /// 1 = Пн … 7 = Вс, matching `DateTime.weekday`.
  static const List<String> _dayTabs = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  int _day = 1;
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
      final page = await KodikApi.instance.browseFiltered(
        CatalogFilter(types: KodikCatalog.all, sort: CatalogSort.updated),
        limit: 100,
      );
      if (!mounted) return;
      final grouped = <int, List<KodikTitle>>{};
      for (final title in KodikApi.dedupe(page.results)) {
        final weekday = title.updatedAt?.weekday;
        if (weekday == null) continue;
        grouped.putIfAbsent(weekday, () => <KodikTitle>[]).add(title);
      }
      setState(() {
        _byDay
          ..clear()
          ..addAll(grouped);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'В этот день обновлений не было',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary),
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
      title: 'Расписание',
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Обновления дорам по дням недели',
                style: TextStyle(fontSize: 13.5, color: AppColors.textTertiary),
              ),
            ),
          ),
          UnderlineTabs(
            tabs: _dayTabs,
            selected: _day - 1,
            onChanged: (i) => setState(() => _day = i + 1),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
