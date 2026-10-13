import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../core/models.dart';
import '../../core/net.dart';
import '../../core/backend_session.dart';
import '../../core/backend_comments.dart';
import '../account/account_screen.dart';
import '../comments/episode_comments_screen.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import 'player_embed.dart';

/// Episode player.
///
/// The Kodik page is rendered by a platform-specific [PlayerEmbed] (WebView on
/// mobile, `<iframe>` on web, system browser on Windows/Linux). If a direct
/// `.m3u8` / `.mp4` ever surfaces in the top frame it is handed to the native
/// [VideoPlayerController] for proper seek and fullscreen controls.
class PlayerScreen extends StatefulWidget {
  final KodikTitle title;
  final List<KodikEpisodeRef> episodes;
  final int initialIndex;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.episodes,
    this.initialIndex = 0,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _Mode { loading, native, web, error }

class _Cancelled implements Exception {
  const _Cancelled();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late int _index;
  _Mode _mode = _Mode.loading;
  VideoPlayerController? _vc;
  String? _playerUrl;
  final Set<String> _seen = <String>{};
  final Set<VideoPlayerController> _controllers = <VideoPlayerController>{};
  final Map<VideoPlayerController, Future<void>> _pendingPlay = {};
  int _generation = 0;
  Completer<void> _cancel = Completer<void>();
  bool _openingNative = false;
  bool _playbackStarted = false;
  bool _preferWeb = false;
  bool _foreground = true;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  String? _error;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex
        .clamp(0, widget.episodes.isEmpty ? 0 : widget.episodes.length - 1);
    unawaited(_open(_index));
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    if (!_cancel.isCompleted) _cancel.complete();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(_saveProgress());
    for (final c in _controllers.toList()) {
      _release(c);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      final vc = _vc;
      if (vc != null) unawaited(vc.pause().catchError((Object _) {}));
      unawaited(_saveProgress());
    }
  }

  bool _isCurrent(int request) => mounted && request == _generation;

  KodikEpisodeRef? get _episode =>
      widget.episodes.isEmpty ? null : widget.episodes[_index];

  // ------------------------------------------------------------ lifecycle

  void _release(VideoPlayerController controller) {
    if (!_controllers.remove(controller)) return;
    final pending = _pendingPlay[controller];
    unawaited(() async {
      try {
        await controller.pause();
      } catch (_) {}
      if (pending != null) {
        try {
          await pending.timeout(const Duration(seconds: 30));
        } catch (_) {}
        // A pending play may have completed after the first pause.
        try {
          await controller.pause();
        } catch (_) {}
      }
      try {
        await controller.dispose();
      } catch (_) {}
    }());
  }

  Future<void> _play(VideoPlayerController controller) {
    final existing = _pendingPlay[controller];
    if (existing != null) return existing;
    final pending = controller.play();
    _pendingPlay[controller] = pending;
    return pending.whenComplete(() => _pendingPlay.remove(controller));
  }

  Future<void> _wait(Future<void> action, Future<void> cancelled) =>
      Future.any<void>([
        action,
        cancelled.then<void>((_) => throw const _Cancelled()),
      ]).timeout(const Duration(seconds: 30));

  Future<void> _saveProgress() async {
    final ep = _episode;
    if (ep == null || !_playbackStarted) return;
    // Capture the controller's value before awaiting storage or changing episode.
    var ms = _vc?.value.position.inMilliseconds;
    if (ms == null) {
      // An embed does not report its position. Keep any known checkpoint for
      // this exact episode instead of replacing it with an unknown zero.
      await Library.registerTitle(widget.title.ref);
      final checkpoint = await Library.episodeCheckpoint(
          widget.title.id, ep.season, ep.episode);
      ms = checkpoint?.positionMs;
    }
    await Library.record(WatchEntry(
      title: widget.title.ref,
      season: ep.season,
      episode: ep.episode,
      positionMs: ms ?? 0,
      watchedAt: DateTime.now(),
    ));
  }

  // -------------------------------------------------------------- opening

  Future<void> _open(int index) async {
    if (!mounted) return;
    // Invalidates every in-flight native attempt for the previous episode.
    final request = ++_generation;
    if (!_cancel.isCompleted) _cancel.complete();
    _cancel = Completer<void>();
    _hideTimer?.cancel();
    // Persist the checkpoint while the outgoing controller is still alive.
    await _saveProgress();
    if (!_isCurrent(request)) return;
    for (final c in _controllers.toList()) {
      _release(c);
    }

    _vc = null;
    _playerUrl = null;
    _openingNative = false;
    _playbackStarted = false;
    _preferWeb = false;
    _seen.clear();
    _index = index.clamp(
        0, widget.episodes.isEmpty ? 0 : widget.episodes.length - 1);
    setState(() {
      _mode = _Mode.loading;
      _error = null;
      _controlsVisible = true;
    });

    final ep = _episode;
    if (ep == null || ep.url.isEmpty) {
      setState(() {
        _mode = _Mode.error;
        _error = 'Ссылка на серию отсутствует';
      });
      return;
    }
    _openWeb(ep.url);
  }

  /// Hands the episode's Kodik page to the platform embed.
  void _openWeb(String url) {
    setState(() {
      _mode = _Mode.web;
      _error = null;
      _playerUrl = url;
    });
  }

  static bool _isHttpMedia(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static bool _isStream(String url) =>
      _isHttpMedia(url) &&
      RegExp(r'\.(m3u8|mp4)$', caseSensitive: false)
          .hasMatch(Uri.parse(url).path);

  void _onSniffed(String url, int request) {
    if (!_isCurrent(request) ||
        _openingNative ||
        _preferWeb ||
        !_foreground ||
        _mode == _Mode.native ||
        !_isStream(url) ||
        !_seen.add(url)) {
      return;
    }
    unawaited(_openNative(url, request));
  }

  Future<void> _openNative(String url, int request) async {
    if (!_isCurrent(request) || _openingNative) return;
    _openingNative = true;
    final cancelled = _cancel.future;
    final episode = _episode;
    if (episode == null) {
      _openingNative = false;
      return;
    }
    VideoPlayerController? controller;
    try {
      final active = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: const {
          'Referer': 'https://kodikplayer.com/',
          'Origin': 'https://kodikplayer.com',
        },
      );
      controller = active;
      _controllers.add(active);
      await _wait(active.initialize(), cancelled);
      if (!_isCurrent(request)) return;
      await Library.registerTitle(widget.title.ref);
      final checkpoint = await Library.episodeCheckpoint(
          widget.title.id, episode.season, episode.episode);
      if (!_isCurrent(request)) return;
      if (checkpoint != null) {
        final durationMs = active.value.duration.inMilliseconds;
        final positionMs = checkpoint.positionMs.clamp(
            0, durationMs > 0
                ? durationMs
                : checkpoint.positionMs.clamp(0, 1 << 53));
        if (positionMs > 0) {
          await _wait(
              active.seekTo(Duration(milliseconds: positionMs)), cancelled);
        }
      }
      if (!_isCurrent(request) || !_foreground || _preferWeb) return;
      await _wait(_play(active), cancelled);
      if (!_isCurrent(request) || !_foreground || _preferWeb) return;

      setState(() {
        _mode = _Mode.native;
        _vc = active;
        _playbackStarted = true;
      });
      active.addListener(() {
        if (_isCurrent(request) && _vc == active && active.value.hasError) {
          unawaited(_saveProgress());
          setState(() {
            _vc = null;
            _mode = _Mode.error;
            _error = 'Воспроизведение прервано';
          });
          _release(active);
        }
      });
      _armAutoHide();
      unawaited(_saveProgress());
    } catch (_) {
      // Native playback failed. Kodik's own web player is still on screen and
      // remains fully usable, so there is nothing to report to the user.
    } finally {
      if (controller != null && (!_isCurrent(request) || _vc != controller)) {
        _release(controller);
      }
      if (_isCurrent(request)) _openingNative = false;
    }
  }

  // ------------------------------------------------------------- controls

  void _armAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleFullscreen() {
    _fullscreen = !_fullscreen;
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    setState(() {});
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.episodes.length) return;
    unawaited(_open(index));
  }

  /// Drops the native stream and returns to Kodik's own player.
  Future<void> _useWebPlayer() async {
    if (_episode == null || !mounted) return;
    final request = ++_generation;
    if (!_cancel.isCompleted) _cancel.complete();
    _cancel = Completer<void>();
    _hideTimer?.cancel();
    _preferWeb = true;
    _openingNative = false;
    final outgoing = _vc;
    await _saveProgress();
    if (!_isCurrent(request)) return;
    // Stop native audio before the iframe is mounted.
    if (outgoing != null) {
      try {
        await outgoing.pause();
      } catch (_) {}
      _release(outgoing);
    }
    if (!_isCurrent(request)) return;
    setState(() {
      _vc = null;
      _mode = _Mode.web;
      _error = null;
    });
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: GestureDetector(
                onTap: _mode == _Mode.native
                    ? () {
                        setState(() => _controlsVisible = !_controlsVisible);
                        if (_controlsVisible) _armAutoHide();
                      }
                    : null,
                child: Stack(
                  children: [
                    Center(child: _surface()),
                    if (_mode == _Mode.native && _vc != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: _nativeControls(_vc!),
                          ),
                        ),
                      ),
                    if (_mode == _Mode.loading)
                      const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white70)),
                  ],
                ),
              ),
            ),
            _episodeStrip(),
          ],
        ),
      ),
    );
  }

  Future<void> _openComments() async {
    final episode = _episode;
    final origin = Net.backendOrigin;
    if (episode == null || origin == null) return;
    try {
      await Library.registerTitle(widget.title.ref);
      final workKey = await Library.workId(widget.title.id);
      final controller = _vc;
      if (controller != null) await controller.pause();
      await _saveProgress();
      if (!mounted || Net.backendOrigin != origin) return;
      final session = BackendSession.forOrigin(origin);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => EpisodeCommentsScreen(
          api: BackendComments(
            origin: origin,
            token: () => session.token,
            userId: () => session.userId,
          ),
          workKey: workKey,
          season: episode.season,
          episode: episode.episode,
          onSignIn: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AccountScreen(origin: origin, session: session),
            ));
          },
        ),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть комментарии')),
        );
      }
    }
  }

  Widget _topBar() {
    final ep = _episode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  ep?.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (Net.backendOrigin != null && ep != null)
            IconButton(
              tooltip: 'Комментарии к серии',
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              onPressed: _openComments,
            ),
          if (_mode == _Mode.native)
            TextButton(
              onPressed: _useWebPlayer,
              child: const Text('Веб-плеер',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  Widget _surface() {
    if (_mode == _Mode.error) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? 'Ошибка воспроизведения',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _open(_index),
              child: const Text('Повторить',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      );
    }
    if (_mode == _Mode.native) {
      final vc = _vc;
      if (vc == null) return const SizedBox.shrink();
      return AspectRatio(
          aspectRatio: vc.value.aspectRatio, child: VideoPlayer(vc));
    }
    final url = _playerUrl;
    if (url == null) return const SizedBox.shrink();
    final request = _generation;
    return PlayerEmbed(
      key: ValueKey<String>(url),
      url: url,
      onStream: (stream) => _onSniffed(stream, request),
      onError: (message) {
        if (!_isCurrent(request) || _mode == _Mode.native) return;
        setState(() {
          _mode = _Mode.error;
          _error = message;
        });
      },
    );
  }

  Widget _nativeControls(VideoPlayerController vc) {
    return Container(
      color: Colors.black38,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: vc,
            builder: (context, value, _) {
              final dur = value.duration;
              final max = dur.inMilliseconds.toDouble();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: [
                    Text(_fmt(value.position),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    Expanded(
                      child: Slider(
                        value: max > 0
                            ? value.position.inMilliseconds
                                .clamp(0, dur.inMilliseconds)
                                .toDouble()
                            : 0,
                        max: max > 0 ? max : 1,
                        activeColor: AppColors.accent,
                        inactiveColor: Colors.white24,
                        onChanged: (v) =>
                            vc.seekTo(Duration(milliseconds: v.toInt())),
                      ),
                    ),
                    Text(_fmt(dur),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_index > 0)
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white, size: 32),
                  onPressed: () => _goTo(_index - 1),
                ),
              const SizedBox(width: 14),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: vc,
                builder: (context, value, _) => GestureDetector(
                  onTap: () => unawaited(
                      (value.isPlaying ? vc.pause() : _play(vc))
                          .catchError((Object _) {})),
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              if (_index < widget.episodes.length - 1)
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white, size: 32),
                  onPressed: () => _goTo(_index + 1),
                ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(
                  _fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _episodeStrip() {
    if (widget.episodes.length < 2) return const SizedBox.shrink();
    return Container(
      color: AppColors.bg,
      height: 78,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        itemCount: widget.episodes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ref = widget.episodes[i];
          final active = i == _index;
          return GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: 52,
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${ref.episode}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}
