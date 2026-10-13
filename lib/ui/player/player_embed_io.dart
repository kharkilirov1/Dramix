import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart' show UnmodifiableListView;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme.dart';
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

  /// Fires when a direct `.m3u8` / `.mp4` URL surfaces.
  final void Function(String streamUrl) onStream;

  /// Fires when the embed itself cannot be shown.
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
  static const String _channel = 'DramixSniffer';

  /// Media hooks shared by both engines. `post` is defined by [_sniffJs].
  static const String _sniffBody = r'''
  var re = /\.(m3u8|mp4)(\?|$)/i;
  var of = window.fetch;
  window.fetch = function(input){
    try {
      var u = typeof input === 'string' ? input : (input && input.url) || '';
      if (re.test(u)) post(u);
    } catch(e){}
    return of.apply(this, arguments);
  };
  var oo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(m, u){
    try { if (re.test(String(u))) post(u); } catch(e){}
    return oo.apply(this, arguments);
  };
  try {
    var d = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    Object.defineProperty(HTMLMediaElement.prototype, 'src', {
      set: function(v){
        try { if (re.test(String(v))) post(v); } catch(e){}
        d.set.call(this, v);
      },
      get: function(){ return d.get.call(this); }
    });
  } catch(e){}
''';

  /// Sniffer for `webview_flutter` (JavaScript channel).
  String get _legacySniffJs =>
      '(function(){if (window.__dramixSniff) return; window.__dramixSniff = true;'
      'var post = function(u){ try { $_channel.postMessage(String(u)); } catch(e){} };'
      '$_sniffBody'
      '})();';

  /// Sniffer for WebView2. Injected into **every** frame, which is the only way
  /// to see the stream: Kodik plays inside its own cross-origin iframe.
  String get _inappSniffJs =>
      '(function(){if (window.__dramixSniff) return; window.__dramixSniff = true;'
      'var post = function(u){ try {'
      ' window.flutter_inappwebview.callHandler("$_channel", String(u));'
      ' } catch(e){} };'
      '$_sniffBody'
      '})();';

  WebViewController? _legacy;
  inapp.WebViewEnvironment? _environment;
  bool _environmentReady = false;
  final Set<String> _seen = <String>{};
  bool _failed = false;

  @override
  void initState() {
    super.initState();
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
        _channel,
        onMessageReceived: (msg) => _onSniffed(msg.message),
      );
      await controller.setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          unawaited(
              controller.runJavaScript(_legacySniffJs).catchError((Object _) {}));
          widget.onLoaded?.call();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            widget.onError('Не удалось загрузить плеер Kodik');
          }
        },
        onNavigationRequest: (request) {
          if (_isStream(request.url)) {
            _onSniffed(request.url);
            return NavigationDecision.prevent;
          }
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          // Keep the player; block ad redirects to market://, intent:// …
          const allowed = {'http', 'https', 'about', 'blob', 'data'};
          return allowed.contains(uri.scheme)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ));
      if (!mounted) return;
      await controller.loadHtmlString(buildWrapperHtml(widget.url));
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
        data: buildWrapperHtml(widget.url),
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
      initialUserScripts: UnmodifiableListView<inapp.UserScript>([
        inapp.UserScript(
          source: _inappSniffJs,
          injectionTime: inapp.UserScriptInjectionTime.AT_DOCUMENT_START,
          // WebView2 injects natively, so this reaches the cross-origin player
          // iframe that a JavaScript channel could never touch.
          forMainFrameOnly: false,
        ),
      ]),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: _channel,
          callback: (args) {
            final url = args.isNotEmpty ? '${args.first}' : '';
            if (url.isNotEmpty) _onSniffed(url);
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url?.toString() ?? '';
        if (_isStream(url)) {
          _onSniffed(url);
          return inapp.NavigationActionPolicy.CANCEL;
        }
        return inapp.NavigationActionPolicy.ALLOW;
      },
      onLoadStop: (controller, uri) {
        // The user script already ran at document start; re-running is a no-op
        // thanks to the __dramixSniff guard and covers late navigations.
        unawaited(controller
            .evaluateJavascript(source: _inappSniffJs)
            .catchError((Object _) {}));
        widget.onLoaded?.call();
      },
    );
  }

  // ------------------------------------------------------------------ helpers

  static bool _isStream(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return false;
    }
    return RegExp(r'\.(m3u8|mp4)$', caseSensitive: false).hasMatch(uri.path);
  }

  void _onSniffed(String url) {
    if (!_isStream(url) || !_seen.add(url)) return;
    widget.onStream(url);
  }

  /// Writes the iframe wrapper to a temp file and hands it to the browser.
  Future<void> _openExternally() async {
    try {
      final dir = await Directory.systemTemp.createTemp('dramix_player');
      final file = File('${dir.path}${Platform.pathSeparator}player.html');
      await file.writeAsString(buildWrapperHtml(widget.url));
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
