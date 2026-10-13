import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/playback_provider.dart';

@JS('JSON.stringify')
external JSString? _stringify(JSAny? value);

/// Embeds the Kodik player as a real browser `<iframe>`.
///
/// Web needs no proxy page here: an iframe on our own origin already satisfies
/// Kodik's top-level guard (`isIframe()`), and the browser streams the video
/// natively. Nothing can be sniffed cross-origin, so [onStream] is never called
/// — the Kodik player is the player on this platform.
class PlayerEmbed extends StatefulWidget {
  final String url;
  final void Function(String streamUrl) onStream;
  final void Function(String message) onError;
  final VoidCallback? onLoaded;
  final String sessionId;
  final int epoch;
  final String episodeKey;
  final int season;
  final int episode;
  final int? translationId;
  final bool isMovie;
  final ValueChanged<PlaybackEvent>? onEvent;

  const PlayerEmbed({
    super.key,
    required this.url,
    required this.onStream,
    required this.onError,
    this.onLoaded,
    this.sessionId = '',
    this.epoch = 0,
    this.episodeKey = '',
    this.season = 1,
    this.episode = 1,
    this.translationId,
    this.isMovie = false,
    this.onEvent,
  });

  @override
  State<PlayerEmbed> createState() => _PlayerEmbedState();
}

class _PlayerEmbedState extends State<PlayerEmbed> {
  late final String _viewType;
  late final JSFunction _messageListener;
  web.HTMLIFrameElement? _iframe;
  KodikPlaybackSession? _session;
  int _sequence = 0;

  @override
  void initState() {
    super.initState();
    if (widget.onEvent != null) {
      _session = KodikPlaybackProvider().openSession(
        frameUri: Uri.parse(widget.url), sessionId: widget.sessionId,
        epoch: widget.epoch, episodeKey: widget.episodeKey,
        season: widget.season, episode: widget.episode,
        translationId: widget.translationId, isMovie: widget.isMovie,
      );
    }
    _messageListener = ((web.Event event) {
      if (!mounted || _iframe == null || widget.onEvent == null) return;
      final message = event as web.MessageEvent;
      final frameWindow = _iframe!.contentWindow;
      if (frameWindow == null || message.source != frameWindow) return;
      String? payload;
      try {
        final data = message.data;
        if (data == null) return;
        payload = data.isA<JSString>()
            ? (data as JSString).toDart
            : _stringify(data)?.toDart;
      } catch (_) {
        return;
      }
      if (payload == null || payload.length > 8192) return;
      final parsed = _session?.parseMessage(payload,
        origin: message.origin, sourceVerified: true,
        epoch: widget.epoch, episodeKey: widget.episodeKey,
        sequence: ++_sequence,
      );
      if (parsed != null) widget.onEvent!(parsed);
    }).toJS;
    web.window.addEventListener('message', _messageListener);
    // A unique type per instance lets the user switch episodes without the
    // browser reusing the previous iframe.
    _viewType = 'dramix-player-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = widget.url
        ..allowFullscreen = true
        ..referrerPolicy = 'origin';
      iframe.setAttribute('allow', 'autoplay; fullscreen; encrypted-media');
      iframe.style
        ..border = 'none'
        ..width = '100%'
        ..height = '100%';
      _iframe = iframe;
      return iframe;
    });
    widget.onLoaded?.call();
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _messageListener);
    _iframe = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
