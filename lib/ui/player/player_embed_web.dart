import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

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

  const PlayerEmbed({
    super.key,
    required this.url,
    required this.onStream,
    required this.onError,
    this.onLoaded,
  });

  @override
  State<PlayerEmbed> createState() => _PlayerEmbedState();
}

class _PlayerEmbedState extends State<PlayerEmbed> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
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
      return iframe;
    });
    widget.onLoaded?.call();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
