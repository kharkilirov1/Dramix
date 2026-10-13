import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../player/player_screen.dart';
import '../widgets.dart';


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
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Выберите вариант',
      body: Column(children: [
        const _HintCard(
          text: 'Напротив каждого варианта озвучки указано количество озвученных '
              'серий. Если серия не запускается, попробуйте другой вариант.',
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
                          child: Text('Нет доступных озвучек',
                              style: TextStyle(color: AppColors.textTertiary)))
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
                                            '${v.totalEpisodes ?? 0} эп.',
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
      ]),
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
  Set<String> _startedEpisodes = <String>{};

  @override
  void initState() {
    super.initState();
    _episodes = widget.title.episodeRefs;
    _season = widget.initialSeason;
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    await Library.registerTitle(widget.title.ref);
    final resume = await Library.resumePoint(widget.title.id);
    final history = await Library.history();
    final started = await startedEpisodesForWork(widget.title.ref, history);
    if (!mounted) return;
    setState(() {
      _season ??= resume?.season;
      _startedEpisodes = started;
    });
  }

  Future<void> _open(int index) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          title: widget.title,
          episodes: _episodes,
          initialIndex: index,
        ),
      ),
    );
    if (mounted) await _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.title.translation;
    final studio = t?.title ?? 'Источник';
    final seasons = _episodes.map((e) => e.season).toSet().toList()..sort();
    final selected = seasons.contains(_season)
        ? _season
        : (seasons.isEmpty ? null : seasons.first);
    final visible = _episodes.where((e) => e.season == selected).toList();
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
        child: Column(children: [
          SizedBox(
            height: 64,
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
                    Text('Источник $studio',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_vert_rounded,
                    size: 24, color: AppColors.textSecondary),
                onPressed: _episodes.length < 2
                    ? null
                    : () => setState(() => _descending = !_descending),
              ),
            ]),
          ),
          const Divider(height: 1, color: AppColors.outline),
          if (widget.title.isSerial && seasons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButton<int>(
                value: selected,
                isExpanded: true,
                items: [
                  for (final season in seasons)
                    DropdownMenuItem(
                      value: season,
                      child: Text('Сезон $season'),
                    ),
                ],
                onChanged: (season) => setState(() => _season = season),
              ),
            ),
          Expanded(
            child: _episodes.isEmpty
                ? const Center(
                    child: Text('Нет эпизодов',
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
                          text: 'Если серия не запускается, попробуйте другую '
                              'озвучку. Реклама в видео к приложению отношения '
                              'не имеет.',
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
                                !widget.title.isSerial && _episodes.length == 1
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
                              const Text('Начат просмотр',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
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
