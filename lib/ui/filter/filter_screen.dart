import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/premium.dart';
import '../../core/theme.dart';
import '../premium/paywall_screen.dart';
import '../widgets.dart';

/// Фильтр (эталон: screenshot 15): outlined-дропдауны, Сбросить + Применить.
///
/// Всегда возвращает `CatalogFilter` через `Navigator.pop`; `types` заполнен
/// всегда (по умолчанию — дорамы).
///
/// Часть полей входит в платный тариф: страна, жанры, возраст, минимальный
/// рейтинг и «скрыть просмотренное». Категория, статус, год и сортировка
/// остаются бесплатными, чтобы каталог был полезен и без подписки.
class FilterScreen extends StatefulWidget {
  /// Reopens the screen on an existing filter instead of a blank one.
  final CatalogFilter? initial;

  const FilterScreen({super.key, this.initial});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  static const Map<String, String> _categories = <String, String>{
    'Дорамы': KodikCatalog.dramas,
    'Фильмы': KodikCatalog.movies,
    'Аниме': KodikCatalog.anime,
    'Мультфильмы': KodikCatalog.cartoons,
    'Всё': KodikCatalog.all,
  };

  static const Map<String, String> _statuses = <String, String>{
    'Вышел': 'released',
    'Выходит': 'ongoing',
    'Анонс': 'anons',
  };

  static final List<String> _years = <String>[
    for (var y = 2027; y >= 1960; y--) '$y',
  ];

  static const List<String> _ages = <String>['0', '6', '12', '16', '18'];
  static const List<String> _ratings = <String>['5', '6', '7', '8', '9'];

  late CatalogFilter _filter;
  String _categoryLabel = 'Дорамы';

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _filter = initial?.copy() ?? CatalogFilter();
    _categoryLabel = _categories.entries
        .firstWhere((e) => e.value == _filter.types,
            orElse: () => const MapEntry<String, String>('Дорамы', ''))
        .key;
  }

  bool get _unlocked => Premium.isPremium;

  String? get _statusLabel {
    for (final entry in _statuses.entries) {
      if (entry.value == _filter.allStatus) return entry.key;
    }
    return null;
  }

  void _apply() => Navigator.pop(context, _filter);

  void _reset() {
    setState(() {
      _filter = CatalogFilter(types: _filter.types);
      _categoryLabel = _categories.entries
          .firstWhere((e) => e.value == _filter.types,
              orElse: () => const MapEntry<String, String>('Дорамы', ''))
          .key;
    });
  }

  /// Runs [action] only when the tier allows it; otherwise opens the paywall.
  Future<void> _gated(String reason, VoidCallback action) async {
    if (_unlocked) {
      action();
      return;
    }
    await ensurePremium(context, reason: reason);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Фильтр',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!_unlocked) _plusBanner(),
        _dropdown(
          'Категория',
          _categoryLabel,
          _categories.keys.toList(),
          (value) {
            if (value == null) return;
            setState(() {
              _categoryLabel = value;
              _filter.types = _categories[value] ?? KodikCatalog.dramas;
            });
          },
        ),
        _dropdown(
          'Страна',
          _filter.countries.isEmpty
              ? null
              : '${_filter.countries.length}: ${(_filter.countries.toList()..sort()).join(', ')}',
          DramaCountries.all,
          (_) => _gated('Фильтр по странам входит в Dramix Plus.', _pickCountries),
          locked: !_unlocked,
          onTap: _pickCountries,
        ),
        _dropdown(
          'Жанры',
          _filter.genres.isEmpty
              ? null
              : (_filter.genres.toList()..sort()).join(', '),
          DramaGenres.all,
          (_) => _gated('Фильтр по жанрам входит в Dramix Plus.', _pickGenres),
          locked: !_unlocked,
          onTap: _pickGenres,
        ),
        _dropdown(
          'Статус',
          _statusLabel,
          _statuses.keys.toList(),
          (value) => setState(() {
            _filter.allStatus = value == null ? null : _statuses[value];
          }),
        ),
        _dropdown(
          'Сортировка',
          _filter.sort.label,
          <String>[for (final s in CatalogSort.values) s.label],
          (value) => setState(() {
            if (value == null) {
              _filter.sort = CatalogSort.updated;
              return;
            }
            _filter.sort = CatalogSort.values.firstWhere(
                (s) => s.label == value,
                orElse: () => CatalogSort.updated);
          }),
        ),
        _dropdown(
          'Год',
          _filter.year?.toString(),
          _years,
          (value) => setState(() {
            _filter.year = value == null ? null : int.tryParse(value);
          }),
        ),
        _dropdown(
          'Минимальный рейтинг',
          _filter.minRating == null ? null : 'от ${_filter.minRating}',
          _ratings,
          (value) => setState(() {
            _filter.minRating = value == null ? null : double.tryParse(value);
          }),
          locked: !_unlocked,
          onLockedTap: () => _gated(
              'Фильтр по рейтингу входит в Dramix Plus.',
              () => setState(() {})),
        ),
        _dropdown(
          'Возраст',
          _filter.minimalAge == null ? null : 'от ${_filter.minimalAge} лет',
          _ages,
          (value) => setState(() {
            _filter.minimalAge = value == null ? null : int.tryParse(value);
          }),
          locked: !_unlocked,
          onLockedTap: () => _gated(
              'Фильтр по возрасту входит в Dramix Plus.', () => setState(() {})),
        ),
        _switchRow(
          title: 'Скрыть просмотренное',
          value: _filter.hideWatched,
          locked: !_unlocked,
          onChanged: (on) => _gated(
            'Скрытие просмотренного входит в Dramix Plus.',
            () => setState(() => _filter.hideWatched = on),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _reset,
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.outline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              child: const Text('Сбросить', style: TextStyle(fontSize: 15.5)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: LightPillButton(label: 'Применить', onTap: _apply),
          ),
        ]),
      ]),
    );
  }

  Widget _plusBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await ensurePremium(context);
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.statPlans.withOpacity(0.6)),
          ),
          child: const Row(children: [
            Icon(Icons.workspace_premium_rounded,
                size: 20, color: AppColors.statPlans),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Страна, жанры, рейтинг и возраст — в Dramix Plus',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textTertiary),
          ]),
        ),
      ),
    );
  }

  /// Outlined-поле, открывающее шторку выбора; последний пункт — «Неважно».
  Widget _dropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged, {
    bool locked = false,
    VoidCallback? onLockedTap,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (locked) {
            (onLockedTap ?? () => _gated('$label входит в Dramix Plus.', () {}))();
            return;
          }
          if (onTap != null) {
            onTap();
            return;
          }
          showModalBottomSheet<void>(
            context: context,
            backgroundColor: AppColors.surface,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (sheetContext) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
                for (final item in items)
                  ListTile(
                    title: Text(item),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onChanged(item);
                    },
                  ),
                ListTile(
                  title: const Text('Неважно'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onChanged(null);
                  },
                ),
              ]),
            ),
          );
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle:
                const TextStyle(color: AppColors.textTertiary, fontSize: 14),
            filled: true,
            fillColor: AppColors.bg,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.outline)),
            suffixIcon: Icon(
              locked ? Icons.lock_outline : Icons.keyboard_arrow_down,
              color: AppColors.textTertiary,
            ),
          ),
          child: Text(value ?? 'Неважно',
              style: TextStyle(
                  fontSize: 16,
                  color: locked ? AppColors.textTertiary : AppColors.textPrimary)),
        ),
      ),
    );
  }

  Widget _switchRow({
    required String title,
    required bool value,
    required bool locked,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 15.5,
                  color: locked ? AppColors.textTertiary : AppColors.textPrimary)),
        ),
        if (locked)
          IconButton(
            icon: const Icon(Icons.lock_outline,
                size: 20, color: AppColors.textTertiary),
            onPressed: () => onChanged(true),
          )
        else
          Switch(
            value: value,
            activeColor: AppColors.statPlans,
            onChanged: onChanged,
          ),
      ]),
    );
  }

  /// Multi-select sheet reused by countries and genres.
  Future<void> _pickMulti({
    required String title,
    required List<String> options,
    required Set<String> selected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          return SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('$title (${selected.length})',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final option in options)
                      CheckboxListTile(
                        value: selected.contains(option),
                        activeColor: AppColors.statPlans,
                        title: Text(option),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (on) => setSheet(() {
                          if (on == true) {
                            selected.add(option);
                          } else {
                            selected.remove(option);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setSheet(selected.clear),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.outline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Очистить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LightPillButton(
                        label: 'Готово',
                        onTap: () {
                          setState(() {});
                          Navigator.pop(sheetContext);
                        }),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void _pickCountries() =>
      _pickMulti(title: 'Страны', options: DramaCountries.all, selected: _filter.countries);

  void _pickGenres() =>
      _pickMulti(title: 'Жанры', options: DramaGenres.all, selected: _filter.genres);
}
