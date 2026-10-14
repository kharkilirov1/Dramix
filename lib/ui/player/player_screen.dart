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
import '../../core/playback_provider.dart';
import '../../core/playback_progress.dart';
import 'player_embed.dart';
import 'player_wrapper.dart';

/// Episode player.
///
/// The Kodik page is rendered by a platform-specific [PlayerEmbed] (WebView on
/// mobile, WebView2 on Windows, `<iframe>` on web, browser on Linux). Only a
/// explicitly content-bound media resolution may be handed to the native
/// [VideoPlayerController] for proper seek and fullscreen controls.
class PlayerScreen extends StatefulWidget {
  final KodikTitle title;
  final List<KodikEpisodeRef> episodes;
  final int initialIndex;
  final PlaybackProvider provider;

  const PlayerScreen({
    super.key,
    required this.title,
    required this.episodes,
    this.initialIndex = 0,
    this.provider = const KodikPlaybackProvider(),
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
  PlaybackProgressTracker? _progress;
  String _sessionId = '';
  int _eventSequence = 0;
  bool _nativeWasPlaying = false;
  bool _nativeEnded = false;
  int? _lastNativeDuration;
  bool _embedSelectionChanged = false;
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
    final controller = _vc;
    if (controller != null) _sampleNative(controller, _generation);
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    if (!_cancel.isCompleted) _cancel.complete();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(_stopProgress().catchError((Object _) {}));
    for (final c in _controllers.toList()) {
      _release(c);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _nativeEvent(PlaybackEventKind.pause, _generation);
      final vc = _vc;
      if (vc != null) unawaited(vc.pause().catchError((Object _) {}));
      unawaited(_saveProgress().catchError((Object _) {}));
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
    try {
      await _progress?.flush();
    } catch (_) {
      // The tracker retains its failed snapshot for a later retry.
    }
  }

  Future<void> _stopProgress() async {
    final progress = _progress;
    _progress = null;
    try {
      await progress?.close();
    } catch (_) {
      // Storage errors must not prevent stopping or switching playback.
    }
  }

  Future<void> _beginProgress(int request) async {
    await _stopProgress();
    if (!_isCurrent(request)) return;
    final episode = _episode;
    if (episode == null) return;
    final title = widget.title.ref;
    var work = title.workId;
    try {
      await Library.registerTitle(title);
      work = await Library.workId(title.id);
    } catch (_) {
      // Playback remains usable even if the guest library cannot be saved.
    }
    if (!_isCurrent(request)) return;
    _sessionId = createPlaybackBridgeToken();
    _eventSequence = 0;
    _nativeWasPlaying = false;
    _nativeEnded = false;
    _lastNativeDuration = null;
    _progress = PlaybackProgressTracker(
      sessionId: _sessionId, workId: work,
      providerId: widget.provider.id, variantId: title.id,
      season: episode.season, episode: episode.episode,
      save: (snapshot) => Library.record(WatchEntry(
        title: title, season: snapshot.season, episode: snapshot.episode,
        positionMs: snapshot.positionMs, watchedAt: DateTime.now(),
      )),
    );
  }

  void _acceptProgress(PlaybackEvent event, int request) {
    if (!_isCurrent(request) || event.sessionId != _sessionId) return;
    if (!_foreground && event.kind != PlaybackEventKind.pause &&
        event.kind != PlaybackEventKind.ended &&
        event.kind != PlaybackEventKind.error &&
        event.kind != PlaybackEventKind.episodeChanged) return;
    if (event.kind == PlaybackEventKind.episodeChanged &&
        ((event.season != null && event.season != _episode?.season) ||
         (event.episode != null && event.episode != _episode?.episode) ||
         (widget.title.translation != null &&
             event.translationId != widget.title.translation!.id))) {
      unawaited(_stopProgress().catchError((Object _) {}));
      setState(() => _embedSelectionChanged = true);
      return;
    }
    // Provider parsers validate their own source sequence. A single trusted
    // sequence also orders local lifecycle pauses with provider notifications.
    final ordered = PlaybackEvent(
      sessionId: event.sessionId, sequence: ++_eventSequence,
      kind: event.kind, positionMs: event.positionMs,
      durationMs: event.durationMs, season: event.season, episode: event.episode,
      translationId: event.translationId,
    );
    final progress = _progress;
    if (progress != null) {
      unawaited(progress.accept(ordered).catchError((Object _) {}));
    }
  }

  void _nativeEvent(PlaybackEventKind kind, int request,
      {int? positionMs, int? durationMs}) {
    _acceptProgress(PlaybackEvent(
      sessionId: _sessionId, sequence: 0, kind: kind,
      positionMs: positionMs, durationMs: durationMs,
    ), request);
  }

  void _sampleNative(VideoPlayerController controller, int request) {
    if (!_isCurrent(request) || _vc != controller) return;
    final value = controller.value;
    if (!value.isInitialized || value.hasError) return;
    final position = value.position.inMilliseconds;
    final duration = value.duration.inMilliseconds;
    if (_lastNativeDuration != duration) {
      _lastNativeDuration = duration;
      _nativeEvent(PlaybackEventKind.duration, request, durationMs: duration);
    }
    if (value.isPlaying != _nativeWasPlaying) {
      _nativeWasPlaying = value.isPlaying;
      _nativeEvent(value.isPlaying
          ? PlaybackEventKind.play : PlaybackEventKind.pause, request,
          positionMs: position, durationMs: duration);
    }
    _nativeEvent(PlaybackEventKind.time, request,
        positionMs: position, durationMs: duration);
    if (value.isCompleted && !_nativeEnded) {
      _nativeEnded = true;
      _nativeEvent(PlaybackEventKind.ended, request,
          positionMs: position, durationMs: duration);
    } else if (!value.isCompleted) {
      _nativeEnded = false;
    }
  }

  // -------------------------------------------------------------- opening

  Future<void> _open(int index) async {
    if (!mounted) return;
    final outgoingController = _vc;
    if (outgoingController != null) _sampleNative(outgoingController, _generation);
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
    _preferWeb = false;
    _seen.clear();
    _index = index.clamp(
        0, widget.episodes.isEmpty ? 0 : widget.episodes.length - 1);
    setState(() {
      _mode = _Mode.loading;
      _error = null;
      _embedSelectionChanged = false;
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
    await _beginProgress(request);
    if (!_isCurrent(request)) return;
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
    // A player-frame MP4/HLS request can still be an advertisement or preview.
    // Only an explicit content resolver may enable native takeover; Kodik's
    // supported adapter currently has no such capability.
    if (!widget.provider.capabilities.directMediaResolution) return;
    if (!_isCurrent(request) ||
        _openingNative ||
        _preferWeb ||
        !_foreground ||
        _embedSelectionChanged ||
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
      final frameUri = Uri.tryParse(_playerUrl ?? '');
      if (frameUri == null ||
          !widget.provider.supportsFrameUri(frameUri)) return;
      final origin = frameUri.origin;
      final active = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'Referer': '$origin/',
          'Origin': origin,
        },
      );
      controller = active;
      _controllers.add(active);
      await _wait(active.initialize(), cancelled);
      if (!_isCurrent(request) || !_foreground || _preferWeb ||
          _embedSelectionChanged) return;
      // Close the iframe tracker before reading its last checkpoint; otherwise
      // a throttled, newer iframe sample could be lost during native takeover.
      await _beginProgress(request);
      if (!_isCurrent(request) || !_foreground || _preferWeb ||
          _embedSelectionChanged) return;
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
      if (!_isCurrent(request) || !_foreground || _preferWeb ||
          _embedSelectionChanged) return;
      await _wait(_play(active), cancelled);
      if (!_isCurrent(request) || !_foreground || _preferWeb ||
          _embedSelectionChanged) return;

      setState(() {
        _mode = _Mode.native;
        _vc = active;
      });
      active.addListener(() {
        _sampleNative(active, request);
        if (_isCurrent(request) && _vc == active && active.value.hasError) {
          _nativeEvent(PlaybackEventKind.error, request);
          unawaited(_saveProgress().catchError((Object _) {}));
          setState(() {
            _vc = null;
            _mode = _Mode.error;
            _error = 'Воспроизведение прервано';
          });
          _release(active);
          unawaited(_stopProgress().catchError((Object _) {}));
        }
      });
      _sampleNative(active, request);
      _armAutoHide();
      unawaited(_saveProgress().catchError((Object _) {}));
    } catch (_) {
      // Native playback failed. Kodik's own web player is still on screen and
      // remains fully usable, so there is nothing to report to the user.
      if (_isCurrent(request) && _mode == _Mode.web &&
          !_embedSelectionChanged) {
        await _beginProgress(request);
        if (_isCurrent(request)) setState(() {});
      }
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
    final activeController = _vc;
    if (activeController != null) _sampleNative(activeController, _generation);
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
    await _beginProgress(request);
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
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = _fullscreen || constraints.maxHeight < 400;
          return Column(
          children: [
            _topBar(compact: compact),
            if (_embedSelectionChanged)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Серия/озвучка изменилась в плеере. Выберите её в Dramix, '
                  'чтобы сохранять историю.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
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
            if (!compact && _mode == _Mode.web && !widget.provider.capabilities.resumeSeek)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('Точная позиция не восстанавливается автоматически в веб-плеере.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 12))),
            if (!compact) _episodeStrip(),
          ],
        );
        }),
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
      final comments = BackendComments(
        origin: origin,
        token: () => session.token,
        userId: () => session.userId,
      );
      try {
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => EpisodeCommentsScreen(
            api: comments,
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
      } finally {
        comments.close();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть комментарии')),
        );
      }
    }
  }

  Widget _topBar({bool compact = false}) {
    final ep = _episode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Назад к сериям',
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
                  ep?.label ?? 'Нет доступной серии',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                if (widget.title.translation != null)
                  Text(
                    '${widget.title.translation!.isVoice ? 'Озвучка' : 'Субтитры'} · ${widget.title.translation!.title}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          if (compact && widget.episodes.length > 1)
            PopupMenuButton<int>(
              tooltip: 'Выбрать сезон и серию',
              icon: const Icon(Icons.playlist_play_rounded, color: Colors.white),
              initialValue: _index,
              onSelected: _goTo,
              itemBuilder: (_) => [
                for (var i = 0; i < widget.episodes.length; i++)
                  PopupMenuItem(value: i,
                    child: Text(widget.episodes[i].label)),
              ],
            ),
          if (compact && _mode == _Mode.web && !widget.provider.capabilities.resumeSeek)
            const Tooltip(
              message: 'Точная позиция не восстанавливается автоматически в веб-плеере.',
              child: Padding(padding: EdgeInsets.all(8),
                child: Icon(Icons.info_outline, color: Colors.white60, size: 20))),
          if (Net.backendOrigin != null && ep != null)
            IconButton(
              tooltip: 'Комментарии к серии',
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              onPressed: _openComments,
            ),
          if (_mode == _Mode.native)
            IconButton(
              tooltip: 'Вернуться в веб-плеер',
              onPressed: _useWebPlayer,
              icon: const Icon(Icons.web_rounded, color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Widget _surface() {
    if (_mode == _Mode.error) {
      return SingleChildScrollView(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
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
            if (_episode != null && _episode!.url.isNotEmpty)
              TextButton(
                onPressed: () => _open(_index),
                child: const Text('Повторить',
                    style: TextStyle(color: Colors.white)),
              )
            else
              TextButton(onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Вернуться к выбору серии')),
          ],
        ),
      )));
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
      key: ValueKey<String>('$_sessionId:$url'),
      url: url,
      provider: widget.provider,
      sessionId: _sessionId,
      epoch: request,
      episodeKey: '${widget.title.id}:${_episode!.season}:${_episode!.episode}',
      season: _episode!.season,
      episode: _episode!.episode,
      translationId: widget.title.translation?.id,
      isMovie: !widget.title.isSerial,
      onEvent: (event) {
        if (_mode == _Mode.web) _acceptProgress(event, request);
      },
      onStream: (stream) => _onSniffed(stream, request),
      onError: (message) {
        if (!_isCurrent(request) || _mode == _Mode.native) return;
        _nativeEvent(PlaybackEventKind.error, request);
        unawaited(_stopProgress().catchError((Object _) {}));
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
                        onChanged: (v) {
                          _nativeEvent(PlaybackEventKind.seek, _generation,
                              positionMs: v.toInt());
                          unawaited(vc.seekTo(Duration(milliseconds: v.toInt()))
                              .catchError((Object _) {}));
                        },
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
                  tooltip: 'Предыдущая серия',
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white, size: 32),
                  onPressed: () => _goTo(_index - 1),
                ),
              const SizedBox(width: 14),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: vc,
                builder: (context, value, _) => Semantics(
                  button: true, label: value.isPlaying ? 'Пауза' : 'Воспроизвести',
                  child: GestureDetector(
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
                )),
              ),
              const SizedBox(width: 14),
              if (_index < widget.episodes.length - 1)
                IconButton(
                  tooltip: 'Следующая серия',
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white, size: 32),
                  onPressed: () => _goTo(_index + 1),
                ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: _fullscreen ? 'Выйти из полного экрана' : 'Полный экран',
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
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Container(
      color: AppColors.bg,
      height: 88 * scale,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        itemCount: widget.episodes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ref = widget.episodes[i];
          final active = i == _index;
          return Semantics(
            button: true, selected: active, label: ref.label,
            child: Material(
              color: active ? AppColors.accent : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _goTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Сезон ${ref.season}',
                        style: const TextStyle(fontSize: 11, color: Colors.white60)),
                      Text('Серия ${ref.episode}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                          color: active ? Colors.white : AppColors.textSecondary)),
                    ]),
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
