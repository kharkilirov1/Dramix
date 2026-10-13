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
      final full = await KodikApi.instance.byId(widget.ref.id);
      if (!mounted) return;
      if (full == null) {
        setState(() => _error = 'Тайтл больше недоступен на Kodik');
        return;
      }
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
  bool _favorite = false;
  int? _status;
  int? _rating;
  WatchEntry? _resume;
  bool _expanded = false;
  bool _loading = true;

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
    try {
      final full = await KodikApi.instance.byId(widget.title.id);
      if (!mounted) return;
      if (full != null) {
        setState(() => _title = full);
        unawaited(_loadVersions(full));
      }
    } catch (_) {
      // The preview record is already good enough to render the page.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVersions(KodikTitle source) async {
    try {
      final list = await KodikApi.instance.versions(source);
      if (!mounted || list.isEmpty) return;
      final found = list.indexWhere((e) => e.id == source.id);
      setState(() {
        _versions = list;
        _versionIndex = found < 0 ? 0 : found;
      });
    } catch (_) {
      // Voice-over switching is a bonus; a failure must not break the page.
    }
  }

  Future<void> _loadLocal() async {
    final favorite = await Library.isFavorite(widget.title.id);
    final status = await Library.watchStatus(widget.title.id);
    final rating = await Library.rating(widget.title.id);
    final resume = await Library.resumePoint(widget.title.id);
    if (!mounted) return;
    setState(() {
      _favorite = favorite;
      _status = status;
      _rating = rating;
      _resume = resume;
    });
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

  int _resumeIndex(List<KodikEpisodeRef> refs) {
    final r = _resume;
    if (r == null) return 0;
    final i =
        refs.indexWhere((e) => e.season == r.season && e.episode == r.episode);
    return i < 0 ? 0 : i;
  }

  Future<void> _play({int? index}) async {
    final active = _active;
    if (index == null && _versions.length > 1) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => VoiceoverScreen(title: _title)),
      );
      if (mounted) await _loadLocal();
      return;
    }
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
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 30)
                      ],
                    ),
                    child: Poster(
                        url: r.image, width: 220, height: 324, radius: 18),
                  ),
                ),
                const SizedBox(height: 18),
                _titleBlock(r),
                const SizedBox(height: 16),
                _pillsRow(r, refs.length),
                const SizedBox(height: 14),
                _playRow(refs),
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
                const SizedBox(height: 14),
                _infoRows(r),
                if (r.genreList.isNotEmpty) _genres(r),
                if ((r.description ?? '').isNotEmpty) _description(r),
                if (_versions.isNotEmpty) _voices(),
                if (refs.isNotEmpty) _episodes(refs),
                if (r.material != null) _ratingBlock(r),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- sections

  Widget _titleBlock(KodikTitle r) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.titleRu,
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Row(children: [
              Flexible(
                child: Text(r.titleOrig ?? '',
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _tag(r.typeLabel),
              if ((r.material?.minimalAge ?? 0) > 0) ...[
                const SizedBox(width: 6),
                _tag('${r.material!.minimalAge}+'),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pillsRow(KodikTitle r, int episodes) {
    final listStatus = WatchStatus.fromValue(_status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: OutlinedButton(
            onPressed: _pickStatus,
            style: _pillStyle,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(listStatus?.title ?? 'Не смотрю',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down, size: 18),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: OutlinedButton(
            onPressed: _toggleFavorite,
            style: _pillStyle,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${r.totalEpisodes ?? episodes}',
                  style: const TextStyle(fontSize: 14.5)),
              const SizedBox(width: 8),
              Icon(
                _favorite
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                size: 17,
                color: _favorite ? AppColors.statPlans : null,
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: OutlinedButton(
            onPressed: null,
            style: _pillStyle,
            child: Text('${r.totalEpisodes ?? 0} эп.',
                style: const TextStyle(fontSize: 13.5)),
          ),
        ),
      ]),
    );
  }

  Widget _playRow(List<KodikEpisodeRef> refs) {
    final available = refs.isNotEmpty;
    final resume = _resume;
    final label = !available
        ? 'Нет доступных серий'
        : (resume == null || resume.title.id != _active.id
            ? 'Воспроизвести'
            : 'Продолжить · ${refs[_resumeIndex(refs)].label}');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: available
              ? LightPillButton(
                  icon: Icons.play_arrow_rounded,
                  label: label,
                  onTap: _play,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 8),
          child: Text('Озвучка',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _versions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final v = _versions[i];
              final t = v.translation;
              final name = t == null
                  ? 'Вариант ${i + 1}'
                  : (t.isVoice || _mentionsSubtitles(t.title)
                      ? t.title
                      : '${t.title} · субтитры');
              final active = i == _versionIndex;
              return GestureDetector(
                onTap: () => setState(() => _versionIndex = i),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: active ? AppColors.accent : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Center(
                    child: Text(name,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: active
                                ? Colors.white
                                : AppColors.textSecondary)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _episodes(List<KodikEpisodeRef> refs) {
    final shown = refs.length > 24 ? 24 : refs.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Row(children: [
            const Text('Серии',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('${refs.length}',
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textTertiary)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => EpisodesScreen(title: _active)),
              ),
              child: const Text('Все серии',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textSecondary)),
            ),
          ]),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 74,
            childAspectRatio: 1.35,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: shown,
          itemBuilder: (context, i) {
            final ref = refs[i];
            final watched = _isWatched(ref);
            return GestureDetector(
              onTap: () => _play(index: i),
              child: Container(
                decoration: BoxDecoration(
                  color: watched ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text('${ref.episode}',
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

  bool _isWatched(KodikEpisodeRef ref) {
    final r = _resume;
    if (r == null || r.title.id != _active.id) return false;
    if (r.season != ref.season) return false;
    return r.episode != null && ref.episode < r.episode!;
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
        padding: const EdgeInsets.symmetric(vertical: 11),
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
    return Material(
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
    );
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
