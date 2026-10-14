import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../player/player_screen.dart';
import '../widgets.dart';
import 'voiceover_screen.dart';

/// Opens the detail page for a catalog entry.
Future<void> openTitle(BuildContext context, KodikTitle title) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TitleScreen(title: title)),
  );
}

/// Opens a title from a locally stored snapshot.
///
/// The snapshot only carries id/title/poster, so the full record (with seasons
/// and episodes) is fetched on the way in.
Future<void> openSavedTitle(BuildContext context, SavedTitleRef ref) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TitleLoaderScreen(ref: ref)),
  );
}

/// Fetches a full record by id, then swaps itself out for [TitleScreen].
class TitleLoaderScreen extends StatefulWidget {
  final SavedTitleRef ref;

  const TitleLoaderScreen({super.key, required this.ref});

  @override
  State<TitleLoaderScreen> createState() => _TitleLoaderScreenState();
}

class _TitleLoaderScreenState extends State<TitleLoaderScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      await Library.registerTitle(widget.ref);
      final full = await KodikApi.instance.byId(widget.ref.id);
      if (!mounted) return;
      if (full == null) {
        setState(() => _error = 'Тайтл больше недоступен на Kodik');
        return;
      }
      await Library.registerTitle(full.ref);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => TitleScreen(title: full)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: widget.ref.title,
      body: _error == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.textSecondary))
          : ErrorCentered(message: _error!, onRetry: _load),
    );
  }
}

/// Страница релиза: blurred backdrop, centred poster, title + original + age,
/// pills row, play button, info rows, genres, voices, series and rating.
class TitleScreen extends StatefulWidget {
  final KodikTitle title;

  const TitleScreen({super.key, required this.title});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  static const String _removeMarker = '__remove__';

  late KodikTitle _title;
  List<KodikTitle> _versions = const <KodikTitle>[];
  int _versionIndex = 0;
  int? _season;
  Set<String> _startedEpisodes = <String>{};
  bool _favorite = false;
  int? _status;
  int? _rating;
  WatchEntry? _resume;
  bool _expanded = false;
  bool _loading = true;
  bool _localLoading = true;
  bool _versionsLoading = false;
  String? _loadError;
  String? _localError;
  String? _versionsError;
  int _localRequest = 0;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _loadLocal();
    _load();
  }

  KodikTitle get _active =>
      _versions.isEmpty ? _title : _versions[_versionIndex];

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final full = await KodikApi.instance.byId(widget.title.id);
      if (!mounted) return;
      if (full != null) {
        await Library.registerTitle(full.ref);
        if (!mounted) return;
        setState(() => _title = full);
        await _loadLocal();
        if (!mounted) return;
        unawaited(_loadVersions(full));
      } else {
        setState(() => _loadError = 'Не удалось найти обновлённые данные.');
      }
    } catch (_) {
      if (mounted) setState(() => _loadError =
          'Не удалось обновить данные. Показана сохранённая карточка.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVersions(KodikTitle source) async {
    setState(() { _versionsLoading = true; _versionsError = null; });
    try {
      await Library.registerTitle(source.ref);
      final list = await KodikApi.instance.versions(source);
      for (final version in list) {
        await Library.registerTitle(version.ref);
      }
      if (!mounted || list.isEmpty) return;
      final found = list.indexWhere((e) => e.id == _active.id);
      setState(() {
        _versions = list;
        _versionIndex = found < 0 ? 0 : found;
      });
      await _loadLocal();
    } catch (_) {
      if (mounted) setState(() => _versionsError =
          'Не удалось загрузить другие озвучки и субтитры.');
    } finally {
      if (mounted) setState(() => _versionsLoading = false);
    }
  }

  Future<void> _loadLocal() async {
    final request = ++_localRequest;
    final title = _active;
    final id = title.id;
    if (mounted) setState(() { _localLoading = true; _localError = null; });
    try {
      await Library.registerTitle(title.ref);
      final favorite = await Library.isFavorite(id);
      final status = await Library.watchStatus(id);
      final rating = await Library.rating(id);
      final resume = await Library.resumePoint(id);
      final history = await Library.history();
      final started = await startedEpisodesForWork(title.ref, history);
      if (!mounted || request != _localRequest || _active.id != id) return;
      setState(() {
        _startedEpisodes = started;
        _season ??= resume?.season;
        _favorite = favorite; _status = status; _rating = rating; _resume = resume;
      });
    } catch (_) {
      if (mounted && request == _localRequest) setState(() {
        _localError = 'Не удалось прочитать локальную историю.';
        _resume = null;
      });
    } finally {
      if (mounted && request == _localRequest) setState(() => _localLoading = false);
    }
  }

  Future<void> _toggleFavorite() async {
    final now = await Library.toggleFavorite(_active.ref);
    if (!mounted) return;
    setState(() => _favorite = now);
    showMessage(context, now ? 'Добавлено в избранное' : 'Удалено из избранного');
  }

  Future<void> _pickStatus() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Список просмотра',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final s in WatchStatus.values)
            ListTile(
              title: Text(s.title),
              trailing: _status == s.value
                  ? Icon(Icons.check_rounded, color: _statusColor(s))
                  : null,
              onTap: () => Navigator.pop(context, '${s.value}'),
            ),
          const Divider(color: AppColors.outline, height: 1),
          ListTile(
            title: const Text('Убрать из списка'),
            textColor: AppColors.badgeNew,
            onTap: () => Navigator.pop(context, _removeMarker),
          ),
        ]),
      ),
    );
    if (result == null || !mounted) return;

    if (result == _removeMarker) {
      await Library.setWatchStatus(_active.ref, null);
      if (!mounted) return;
      setState(() => _status = null);
      showMessage(context, 'Убрано из списка');
      return;
    }

    final status = WatchStatus.fromValue(int.tryParse(result));
    if (status == null) return;
    await Library.setWatchStatus(_active.ref, status);
    if (!mounted) return;
    setState(() => _status = status.value);
    showMessage(context, 'Список: ${status.title}');
  }

  Future<void> _setRating(int stars) async {
    final next = _rating == stars ? null : stars;
    await Library.setRating(_active.id, next);
    if (!mounted) return;
    setState(() => _rating = next);
    showMessage(context, next == null ? 'Оценка снята' : 'Оценка $next сохранена');
  }

  int _resumeIndex(List<KodikEpisodeRef> refs) =>
      playbackStartIndex(refs, _resume, selectedSeason: _season);

  Future<void> _play({int? index}) async {
    if (_localLoading) return;
    final active = _active;
    final refs = active.episodeRefs;
    if (refs.isEmpty) {
      showMessage(context, 'Для этого тайтла нет доступных серий');
      return;
    }
    final start = (index ?? _resumeIndex(refs)).clamp(0, refs.length - 1);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: active,
          episodes: refs,
          initialIndex: start,
        ),
      ),
    );
    if (mounted) await _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final r = _active;
    final refs = r.episodeRefs;
    final backdrop = r.image;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(
          image: (backdrop ?? '').isEmpty
              ? null
              : DecorationImage(
                  image: CachedNetworkImageProvider(backdrop!),
                  fit: BoxFit.cover,
                  opacity: 0.18),
        ),
        child: SafeArea(
          bottom: false,
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _roundIcon(
                          Icons.arrow_back, () => Navigator.maybePop(context)),
                      _roundIcon(
                          _favorite
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          _toggleFavorite),
                    ],
                  ),
                ),
                _hero(r, refs),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.textTertiary),
                      ),
                    ),
                  ),
                if (_loadError != null) _notice(_loadError!, _load),
                if (_localError != null) _notice(_localError!, _loadLocal),
                if (_versionsError != null)
                  _notice(_versionsError!, () => _loadVersions(_title)),
                if (_versionsLoading)
                  const Padding(padding: EdgeInsets.all(16),
                    child: Text('Загружаем варианты просмотра…',
                      style: TextStyle(color: AppColors.textSecondary))),
                const SizedBox(height: 14),
                _infoRows(r),
                if (r.genreList.isNotEmpty) _genres(r),
                if ((r.description ?? '').isNotEmpty) _description(r),
                if (_versions.isNotEmpty) _voices(),
                if (refs.isNotEmpty) _episodes(refs),
                if (r.material != null) _ratingBlock(r),
                const SizedBox(height: 24),
              ],
            ))),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- sections

  Widget _notice(String message, Future<void> Function() retry) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12,
      children: [Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        TextButton(onPressed: retry, child: const Text('Повторить'))]));

  Widget _hero(KodikTitle title, List<KodikEpisodeRef> refs) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final poster = Padding(padding: const EdgeInsets.all(16),
          child: Poster(url: title.image, width: wide ? 230 : 180,
            height: wide ? 340 : 265, radius: 18));
        final details = Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [_titleBlock(title), const SizedBox(height: 12),
            _playRow(refs), const SizedBox(height: 12),
            _pillsRow(title, refs.length),
            if (_resume != null && _resume!.positionMs > 0 &&
                refs.any((e) => e.season == _resume!.season &&
                    e.episode == _resume!.episode))
              const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text('Сохранённая серия. Точная позиция зависит от плеера.',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary))),
          ]);
        return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start,
          children: [poster, Expanded(child: Padding(
            padding: const EdgeInsets.only(top: 24), child: details))])
          : Column(children: [Center(child: poster), details]);
      });

  Widget _titleBlock(KodikTitle r) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(r.titleRu, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      if ((r.titleOrig ?? '').isNotEmpty && r.titleOrig != r.titleRu)
        Padding(padding: const EdgeInsets.only(top: 6),
          child: Text(r.titleOrig!,
            style: const TextStyle(fontSize: 14, color: AppColors.textSecondary))),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _tag(r.typeLabel),
        if (r.year != null) _tag('${r.year}'),
        if ((r.material?.minimalAge ?? 0) > 0) _tag('${r.material!.minimalAge}+'),
        if ((r.quality ?? '').isNotEmpty) _tag(r.quality!),
      ]),
    ]));

  Widget _pillsRow(KodikTitle r, int episodes) {
    final listStatus = WatchStatus.fromValue(_status);
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _pickStatus, style: _pillStyle,
          icon: const Icon(Icons.list_alt_rounded, size: 18),
          label: Text(listStatus?.title ?? 'Добавить в список')),
        OutlinedButton.icon(onPressed: _toggleFavorite, style: _pillStyle,
          icon: Icon(_favorite ? Icons.bookmark_rounded :
            Icons.bookmark_border_rounded, size: 18),
          label: Text(_favorite ? 'В избранном' : 'В избранное')),
        if (r.isSerial && episodes > 0)
          Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('$episodes доступных серий',
              style: const TextStyle(color: AppColors.textSecondary))),
      ]));
  }

  Widget _playRow(List<KodikEpisodeRef> refs) {
    final available = refs.isNotEmpty;
    final label = _localLoading ? 'Проверяем историю…'
        : playbackActionLabel(refs, _resume, selectedSeason: _season);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: available
              ? LightPillButton(
                  icon: Icons.play_arrow_rounded,
                  label: label,
                  loading: _localLoading,
                  onTap: _localLoading ? null : _play,
                )
              : Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary)),
                ),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
          onPressed: _showMore,
        ),
      ]),
    );
  }

  Widget _infoRows(KodikTitle r) {
    final rows = <(IconData, String)>[
      (Icons.flag_outlined, _countryLine(r)),
      (
        Icons.play_circle_outline,
        '${r.episodesLabel}'
            '${(r.material?.duration ?? 0) > 0 ? ' по ~${r.material!.duration} мин.' : ''}'
      ),
      (Icons.calendar_today_outlined, _typeLine(r)),
      if ((r.material?.actors ?? const <String>[]).isNotEmpty)
        (Icons.groups_outlined, r.material!.actors.take(6).join(', ')),
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(row.$1, size: 19, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(row.$2,
                    style: const TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textSecondary,
                        height: 1.35)),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _genres(KodikTitle r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final g in r.genreList)
            Text(g,
                style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline)),
        ],
      ),
    );
  }

  Widget _description(KodikTitle r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stripHtml(r.description!),
            maxLines: _expanded ? null : 5,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14.5, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Свернуть' : 'Показать полностью',
              style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voices() {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Озвучка и субтитры',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < _versions.length; i++)
            ChoiceChip(
              label: Text(_versions[i].translation == null ? 'Вариант ${i + 1}'
                : (_versions[i].translation!.isVoice ||
                    _mentionsSubtitles(_versions[i].translation!.title)
                  ? _versions[i].translation!.title
                  : '${_versions[i].translation!.title} · субтитры')),
              selected: i == _versionIndex,
              onSelected: (_) async {
                setState(() {
                  _versionIndex = i; _resume = null;
                  _localLoading = true; _startedEpisodes = <String>{};
                });
                await _loadLocal();
              }),
        ]),
      ]));
  }

  Widget _episodes(List<KodikEpisodeRef> refs) {
    final seasons = refs.map((e) => e.season).toSet().toList()..sort();
    final selected = seasons.contains(_season) ? _season! : seasons.first;
    final visible = refs.where((e) => e.season == selected).toList()
      ..sort((a, b) => a.episode.compareTo(b.episode));
    final shown = visible.length > 24 ? 24 : visible.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Row(children: [
            const Text('Серии',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('${visible.length}',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textTertiary)),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => EpisodesScreen(
                        title: _active, initialSeason: selected)),
              ),
              child: const Text('Все серии',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textSecondary)),
            ),
          ]),
        ),
        if (_active.isSerial)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final season in seasons)
                ChoiceChip(
                  label: Text('Сезон $season · ${refs.where((e) => e.season == season).length}'),
                  selected: season == selected,
                  onSelected: (_) => setState(() => _season = season),
                ),
            ]),
          ),
        if (_startedEpisodes.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text('· Начат просмотр',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisExtent: 56 * (MediaQuery.textScalerOf(context).scale(15) / 15),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: shown,
          itemBuilder: (context, i) {
            final ref = visible[i];
            final watched = _startedEpisodes
                .contains('${ref.season}:${ref.episode}');
            return GestureDetector(
              onTap: () => _play(index: refs.indexOf(ref)),
              child: Container(
                decoration: BoxDecoration(
                  color: watched ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(watched ? '${ref.episode} ·' : '${ref.episode}',
                      semanticsLabel: '${ref.label}${watched ? ', начат просмотр' : ''}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: watched
                              ? Colors.white
                              : AppColors.textPrimary)),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _ratingBlock(KodikTitle r) {
    final m = r.material!;
    final score = m.bestRating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 10),
          child: Text('Рейтинг',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            SizedBox(
              width: 92,
              child: Column(children: [
                Text(score == null ? '—' : score.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(m.ratingSource ?? 'нет оценок',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                    textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((m.kinopoiskRating ?? 0) > 0)
                    _ratingLine('Кинопоиск', m.kinopoiskRating!),
                  if ((m.imdbRating ?? 0) > 0)
                    _ratingLine('IMDb', m.imdbRating!),
                  if ((m.shikimoriRating ?? 0) > 0)
                    _ratingLine('Shikimori', m.shikimoriRating!),
                  if (m.ratingMpaa != null)
                    _ratingLine('Возраст', null, text: m.ratingMpaa!),
                ],
              ),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text('Ваша оценка',
              style: TextStyle(fontSize: 14.5, color: AppColors.textSecondary)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                iconSize: 34,
                icon: Icon(
                  (_rating ?? 0) >= star
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: AppColors.statHoldOn,
                ),
                onPressed: () => _setRating(star),
              ),
          ],
        ),
      ],
    );
  }

  Widget _ratingLine(String label, double? value, {String? text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textTertiary)),
        ),
        if (value != null) ...[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (value / 10).clamp(0, 1),
                minHeight: 8,
                backgroundColor: AppColors.surface,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 12.5)),
        ] else
          Expanded(
            child: Text(text ?? '',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _showMore() async {
    final r = _active;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Действия',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.list_alt_rounded),
            title: const Text('Добавить в список'),
            onTap: () => Navigator.pop(context, 'status'),
          ),
          ListTile(
            leading: Icon(_favorite
                ? Icons.bookmark_remove_rounded
                : Icons.bookmark_add_outlined),
            title: Text(_favorite ? 'Убрать из избранного' : 'В избранное'),
            onTap: () => Navigator.pop(context, 'favorite'),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('Выбрать озвучку'),
            onTap: () => Navigator.pop(context, 'voices'),
          ),
          ListTile(
            leading: const Icon(Icons.tag_rounded),
            title: Text('Kodik ID: ${r.id}',
                style: const TextStyle(fontSize: 13.5)),
            onTap: () => Navigator.pop(context),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'status':
        await _pickStatus();
        break;
      case 'favorite':
        await _toggleFavorite();
        break;
      case 'voices':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => VoiceoverScreen(title: _title)),
        );
        if (mounted) await _loadLocal();
        break;
    }
  }

  // ---------------------------------------------------------------- helpers

  ButtonStyle get _pillStyle => OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      );

  /// Studio names often already say "Subtitles"; avoid stating it twice.
  static bool _mentionsSubtitles(String name) {
    final lower = name.toLowerCase();
    return lower.contains('субтитр') || lower.contains('subtitle');
  }

  Color _statusColor(WatchStatus s) => switch (s) {
        WatchStatus.watching => AppColors.statWatching,
        WatchStatus.plans => AppColors.statPlans,
        WatchStatus.completed => AppColors.statCompleted,
        WatchStatus.holdOn => AppColors.statHoldOn,
        WatchStatus.dropped => AppColors.statDropped,
      };

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(7)),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary)),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return Semantics(button: true,
      label: icon == Icons.arrow_back ? 'Назад' :
        (_favorite ? 'Убрать из избранного' : 'В избранное'),
      child: Material(
      color: AppColors.surface.withOpacity(0.9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: AppColors.textPrimary, size: 22)),
      ),
    ));
  }

  String _countryLine(KodikTitle r) {
    final season = switch (r.material?.allStatus) {
      'ongoing' => 'выходит',
      'released' => 'завершён',
      'anons' => 'анонс',
      _ => '',
    };
    final year = r.year?.toString() ?? '';
    return <String>[
      r.material?.countryLabel ?? '',
      if (season.isNotEmpty) '$season $year'.trim() else year,
    ].where((s) => s.isNotEmpty).join(', ');
  }

  String _typeLine(KodikTitle r) {
    final parts = <String>[r.typeLabel];
    if (r.year != null) parts.add('${r.year}');
    if ((r.quality ?? '').isNotEmpty) parts.add(r.quality!);
    if (r.camrip) parts.add('CAMRip');
    return parts.join(', ');
  }
}
