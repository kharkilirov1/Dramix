import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
import '../../core/playback_provider.dart';
import '../widgets.dart';
import 'player_wrapper.dart';

/// Hosts where `webview_flutter` has an implementation.
bool get _hasWebView =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Windows has no `webview_flutter` implementation; WebView2 through
/// `flutter_inappwebview` fills that gap.
bool get _hasWebView2 => Platform.isWindows;

/// Embeds the Kodik player.
///
/// Three platform paths:
///  * Android / iOS / macOS — `webview_flutter` over a local iframe wrapper;
///  * Windows — WebView2 (`flutter_inappwebview`), also over the wrapper;
///  * Linux — no embeddable web view, so the wrapper is handed to the browser.
///
/// Kodik's player hides itself outside an iframe, so every path frames the page
/// through [buildWrapperHtml].
class PlayerEmbed extends StatefulWidget {
  /// The Kodik player page for this episode.
  final String url;

  /// Reserved for an explicit, content-bound resolver. Generic iframe media
  /// URLs are not emitted: advertisements can use the same player origin.
  final void Function(String streamUrl) onStream;

  /// Fires when the embed itself cannot be shown.
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
  static const String _progressChannel = 'DramixProgress';
  late final String _bridgeToken;
  KodikPlaybackSession? _session;
  late final PlaybackBridgeGate _bridgeGate;

  String get _wrapper => buildWrapperHtml(widget.url,
      bridgeToken: _session == null ? null : _bridgeToken,
      sessionId: _session == null ? null : widget.sessionId);

  void _onProgress(String raw) {
    if (!mounted || widget.onEvent == null) return;
    final envelope = _bridgeGate.accept(raw);
    if (envelope == null) return;
    final event = _session?.parseMessage(envelope['payload'],
        origin: envelope['origin'] as String,
        sourceVerified: true,
        epoch: widget.epoch,
        episodeKey: widget.episodeKey,
        sequence: envelope['sequence'] as int);
    if (event != null) widget.onEvent!(event);
  }

  WebViewController? _legacy;
  inapp.WebViewEnvironment? _environment;
  bool _environmentReady = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bridgeToken = createPlaybackBridgeToken();
    _bridgeGate = PlaybackBridgeGate(
      token: _bridgeToken, sessionId: widget.sessionId,
      origin: Uri.parse(widget.url).origin,
    );
    if (widget.onEvent != null) {
      _session = KodikPlaybackProvider().openSession(
        frameUri: Uri.parse(widget.url), sessionId: widget.sessionId,
        epoch: widget.epoch, episodeKey: widget.episodeKey,
        season: widget.season, episode: widget.episode,
        translationId: widget.translationId, isMovie: widget.isMovie,
      );
    }
    if (_hasWebView) unawaited(_bootLegacy());
    if (_hasWebView2) unawaited(_bootEnvironment());
  }

  /// WebView2 keeps its browser profile on disk, and the default location is
  /// next to the executable — read-only when the app is installed under
  /// Program Files, which would break the player for standard users. Point it
  /// at the user's local app data instead, falling back to the default if even
  /// that is unavailable.
  Future<void> _bootEnvironment() async {
    inapp.WebViewEnvironment? environment;
    try {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base != null && base.isNotEmpty) {
        final separator = Platform.pathSeparator;
        final dir = Directory(
            '$base${separator}Dramix${separator}WebView2');
        await dir.create(recursive: true);
        environment = await inapp.WebViewEnvironment.create(
          settings: inapp.WebViewEnvironmentSettings(userDataFolder: dir.path),
        );
      }
    } catch (_) {
      environment = null; // fall back to the WebView2 default
    }
    if (!mounted) return;
    setState(() {
      _environment = environment;
      _environmentReady = true;
    });
  }

  // ------------------------------------------------------------ webview_flutter

  Future<void> _bootLegacy() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.black);
      await controller.addJavaScriptChannel(
        _progressChannel,
        onMessageReceived: (msg) => _onProgress(msg.message),
      );
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          widget.onLoaded?.call();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            widget.onError('Не удалось загрузить плеер Kodik');
          }
        },
        onNavigationRequest: (request) {
          if (_isStream(request.url)) {
            return NavigationDecision.prevent;
          }
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          // Keep the player; block ad redirects to market://, intent:// …
          const allowed = {'http', 'https', 'about', 'blob', 'data'};
          if (request.isMainFrame &&
              (uri.scheme == 'http' || uri.scheme == 'https')) {
            return NavigationDecision.prevent;
          }
          return allowed.contains(uri.scheme)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ));
      if (!mounted) return;
      await controller.loadHtmlString(_wrapper);
      if (mounted) setState(() => _legacy = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onError('Не удалось открыть плеер');
    }
  }

  // ------------------------------------------------------------------- WebView2

  Widget _buildWebView2() {
    return inapp.InAppWebView(
      key: ValueKey<String>(widget.url),
      webViewEnvironment: _environment,
      initialData: inapp.InAppWebViewInitialData(
        data: _wrapper,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: inapp.InAppWebViewSettings(
        javaScriptEnabled: true,
        // The player must be able to start without a tap.
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        transparentBackground: true,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: _progressChannel,
          callback: (args) {
            if (args.length == 1 && args.first is String) {
              _onProgress(args.first as String);
            }
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url?.toString() ?? '';
        if (_isStream(url)) {
          return inapp.NavigationActionPolicy.CANCEL;
        }
        if (action.isForMainFrame == true &&
            (Uri.tryParse(url)?.scheme == 'https' ||
                Uri.tryParse(url)?.scheme == 'http')) {
          return inapp.NavigationActionPolicy.CANCEL;
        }
        return inapp.NavigationActionPolicy.ALLOW;
      },
      onLoadStop: (controller, uri) {
        unawaited(controller.evaluateJavascript(
          source: "window.dispatchEvent(new Event('dramixProgressBridgeReady'));",
        ).catchError((Object _) {}));
        widget.onLoaded?.call();
      },
    );
  }

  // ------------------------------------------------------------------ helpers

  static bool _isStream(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    return RegExp(r'\.(m3u8|mp4)$', caseSensitive: false).hasMatch(uri.path);
  }

  /// Writes the iframe wrapper to a temp file and hands it to the browser.
  Future<void> _openExternally() async {
    try {
      final dir = await Directory.systemTemp.createTemp('dramix_player');
      final file = File('${dir.path}${Platform.pathSeparator}player.html');
      await file.writeAsString(_wrapper);
      final opened =
          await launchUrl(file.uri, mode: LaunchMode.externalApplication);
      if (!opened) widget.onError('Не удалось открыть браузер');
    } catch (_) {
      widget.onError('Не удалось открыть браузер');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasWebView2) {
      if (!_environmentReady) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      }
      return _buildWebView2();
    }
    if (!_hasWebView) return _externalPanel();
    if (_failed) return const SizedBox.shrink();
    final controller = _legacy;
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    return SizedBox.expand(child: WebViewWidget(controller: controller));
  }

  /// Linux: no embeddable web view, so the episode is handed to the system
  /// browser rather than pretending to play inline.
  Widget _externalPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_browser_rounded,
                size: 44, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text(
              'На этой платформе нет встроенного веб-плеера',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Серия откроется в браузере — там плеер Kodik работает полноценно.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            LightPillButton(
              icon: Icons.play_circle_outline_rounded,
              label: 'Открыть в браузере',
              onTap: _openExternally,
            ),
          ],
        ),
      ),
    );
  }
}
