import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../player/player_screen.dart';
import '../widgets.dart';



/// A resume target is usable only when this rendition contains that episode.
/// Without a match, start in the explicitly selected season instead.
int playbackStartIndex(List<KodikEpisodeRef> episodes, WatchEntry? resume,
    {int? selectedSeason}) {
  if (episodes.isEmpty) return 0;
  if (resume != null) {
    final match = episodes.indexWhere((e) =>
        e.season == resume.season && e.episode == resume.episode);
    if (match >= 0) return match;
  }
  final selected = episodes.indexWhere((e) => e.season == selectedSeason);
  return selected < 0 ? 0 : selected;
}

String playbackActionLabel(List<KodikEpisodeRef> episodes, WatchEntry? resume,
    {int? selectedSeason}) {
  if (episodes.isEmpty) return 'Нет доступных серий';
  final index = playbackStartIndex(episodes, resume,
      selectedSeason: selectedSeason);
  final target = episodes[index];
  final matches = resume != null && target.season == resume.season &&
      target.episode == resume.episode;
  return matches && (resume?.positionMs ?? 0) > 0
      ? 'Продолжить · ${target.label}'
      : 'Смотреть · ${target.label}';
}

/// Episode markers use the work identity, while playback retains provider IDs.
/// The newest checkpoint wins, including an explicit reset to zero.
Future<Set<String>> startedEpisodesForWork(
    SavedTitleRef title, List<WatchEntry> history) async {
  final work = await Library.workId(title.id);
  final identities = <String, String>{};
  final seen = <String>{};
  final started = <String>{};
  for (final entry in history) {
    final identity = identities[entry.title.id] ??=
        await Library.workId(entry.title.id);
    if (identity != work) continue;
    final episode = '${entry.season}:${entry.episode}';
    if (!seen.add(episode)) continue;
    if (entry.positionMs > 0) started.add(episode);
  }
  return started;
}

/// Выбор озвучки: full-screen list of the dubbing studios Kodik has for this
/// title, each showing how many episodes it covers.
class VoiceoverScreen extends StatefulWidget {
  final KodikTitle title;

  const VoiceoverScreen({super.key, required this.title});

  @override
  State<VoiceoverScreen> createState() => _VoiceoverScreenState();
}

class _VoiceoverScreenState extends State<VoiceoverScreen> {
  List<KodikTitle> _versions = const <KodikTitle>[];
  bool _loading = true;
  String? _error;

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
      await Library.registerTitle(widget.title.ref);
      final list = await KodikApi.instance.versions(widget.title);
      for (final version in list) {
        await Library.registerTitle(version.ref);
      }
      if (mounted) {
        setState(() {
          _versions = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить варианты просмотра. Проверьте соединение.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Выберите вариант',
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920), child: Column(children: [
        const _HintCard(
          text: 'Выберите озвучку или субтитры, затем сезон и серию. '
              'Доступные серии могут различаться между вариантами.',
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.textSecondary))
              : _error != null
                  ? ErrorCentered(message: _error!, onRetry: _load)
                  : _versions.isEmpty
                      ? const Center(
                          child: Text('Нет доступных вариантов просмотра',
                              style: const TextStyle(color: AppColors.textTertiary)))
                      : ListView.separated(
                          itemCount: _versions.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.outline),
                          itemBuilder: (context, i) {
                            final v = _versions[i];
                            final t = v.translation;
                            final name = t?.title ?? 'Вариант ${i + 1}';
                            final isSub = t != null && !t.isVoice;
                            return InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => EpisodesScreen(title: v)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 18),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 3),
                                        Text(
                                          [
                                            if (v.totalEpisodes != null && v.totalEpisodes! > 0)
                                              '${v.totalEpisodes} серий в каталоге'
                                            else 'Количество серий не указано',
                                            if ((v.quality ?? '').isNotEmpty)
                                              v.quality!,
                                          ].join(' · '),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (v.id == widget.title.id)
                                    const Padding(padding: EdgeInsets.only(right: 8),
                                      child: Icon(Icons.check_circle_outline,
                                        color: AppColors.textSecondary)),
                                  if (isSub)
                                    Container(
                                      margin: const EdgeInsets.only(right: 10),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: AppColors.textTertiary),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Text('СУБТИТРЫ',
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textTertiary)),
                                    ),
                                  const Icon(Icons.chevron_right,
                                      color: AppColors.textTertiary),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      ]))),
    );
  }
}

/// «Выберите серию»: vertical episode list with the voice-over name as a
/// header, matching the reference layout.
class EpisodesScreen extends StatefulWidget {
  final KodikTitle title;

  final int? initialSeason;

  const EpisodesScreen({super.key, required this.title, this.initialSeason});

  @override
  State<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends State<EpisodesScreen> {
  List<KodikEpisodeRef> _episodes = const <KodikEpisodeRef>[];
  int? _season;
  bool _descending = false;
  bool _loading = true;
  String? _error;
  late KodikTitle _title;
  WatchEntry? _resume;
  Set<String> _startedEpisodes = <String>{};

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _episodes = _title.episodeRefs;
    _season = widget.initialSeason;
    _loadLocal();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final full = await KodikApi.instance.byId(widget.title.id);
      if (!mounted) return;
      if (full != null) {
        _title = full;
        _episodes = full.episodeRefs;
      }
      await _loadLocal();
    } catch (_) {
      if (mounted) setState(() =>
        _error = 'Не удалось обновить серии. Доступные данные сохранены.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLocal() async {
    try {
      await Library.registerTitle(_title.ref);
      final resume = await Library.resumePoint(_title.id);
      final history = await Library.history();
      final started = await startedEpisodesForWork(_title.ref, history);
      if (!mounted) return;
      setState(() {
        _season ??= resume?.season;
        _resume = resume;
        _startedEpisodes = started;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось прочитать историю просмотра.');
    }
  }

  Future<void> _open(int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: _title,
          episodes: _episodes,
          initialIndex: index,
        ),
      ),
    );
    if (mounted) await _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final t = _title.translation;
    final studio = t?.title ?? 'Источник';
    final seasons = _episodes.map((e) => e.season).toSet().toList()..sort();
    final selected = seasons.contains(_season)
        ? _season
        : (seasons.isEmpty ? null : seasons.first);
    final visible = _episodes.where((e) => e.season == selected).toList()
      ..sort((a, b) => a.episode.compareTo(b.episode));
    if (_descending) {
      final reversed = visible.reversed.toList();
      visible
        ..clear()
        ..addAll(reversed);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(children: [
          SizedBox(
            height: 64 * (MediaQuery.textScalerOf(context).scale(16) / 16),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: AppColors.textPrimary, size: 26),
                onPressed: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Выберите серию',
                        style: TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w700)),
                    Text(studio,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                tooltip: _descending ? 'Сначала ранние серии' : 'Сначала поздние серии',
                icon: const Icon(Icons.swap_vert_rounded,
                    size: 24, color: AppColors.textSecondary),
                onPressed: _episodes.length < 2
                    ? null
                    : () => setState(() => _descending = !_descending),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.outline),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12),
            child: Column(children: [Text(_error!),
              TextButton(onPressed: _loading ? null : _load, child: const Text('Повторить'))])),
          if (_title.isSerial && seasons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButton<int>(
                value: selected,
                isExpanded: true,
                items: [
                  for (final season in seasons)
                    DropdownMenuItem(
                      value: season,
                      child: Text('Сезон $season · ${_episodes.where((e) => e.season == season).length} серий'),
                    ),
                ],
                onChanged: (season) => setState(() => _season = season),
              ),
            ),
          Expanded(
            child: _episodes.isEmpty
                ? Center(
                    child: Text(_loading ? 'Загружаем серии…' : 'В этом варианте нет доступных серий',
                        style: TextStyle(color: AppColors.textTertiary)))
                : ListView.builder(
                    itemCount: visible.length + 2,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(studio,
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.w800)),
                          ),
                        );
                      }
                      if (i == 1) {
                        return const _HintCard(
                          text: 'Метка «Начат просмотр» обозначает сохранённую позицию, '
                              'а не завершённую серию. Продолжение с точной секунды '
                              'зависит от выбранного плеера.',
                        );
                      }
                      final ref = visible[i - 2];
                      final watched = _startedEpisodes
                          .contains('${ref.season}:${ref.episode}');
                      return InkWell(
                        onTap: () => _open(_episodes.indexOf(ref)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                !_title.isSerial && _episodes.length == 1
                                    ? 'Полнометражный фильм'
                                    : 'Сезон ${ref.season} · Серия ${ref.episode}',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: watched
                                        ? AppColors.badgeNew
                                        : AppColors.textPrimary),
                              ),
                            ),
                            if (watched)
                              Flexible(child: Text(_resume?.season == ref.season &&
                                  _resume?.episode == ref.episode
                                    ? 'Продолжить' : 'Начат просмотр',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary))),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]))),
      ),
    );
  }
}

/// Outlined hint card used on both picker screens.
class _HintCard extends StatelessWidget {
  final String text;

  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('Подсказка',
              style: TextStyle(fontSize: 14.5, color: AppColors.textTertiary)),
          SizedBox(width: 6),
          Icon(Icons.lightbulb_outline,
              size: 15, color: AppColors.textTertiary),
        ]),
        const SizedBox(height: 6),
        Text(text,
            style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textTertiary,
                height: 1.4)),
      ]),
    );
  }
}
