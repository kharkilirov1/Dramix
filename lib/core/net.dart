import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// User-Agent sent to Kodik. A plain Dart client is rejected, a browser-like
/// one is not.
const String appUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// How requests reach `kodik-api.com`.
enum NetMode {
  /// Talk to Kodik directly — native builds, and web served from localhost.
  direct,

  /// Route through a JSON-wrapping proxy: it replies
  /// `{"contents": "<body>", "status": {"http_code": N}}`.
  wrap,

  /// Route through a plain prefix proxy that returns the body unchanged.
  prefix,
}

/// Network routing.
///
/// `kodik-api.com` sends **no** `Access-Control-Allow-Origin`, so a browser
/// build cannot read its responses at all: the browser blocks them before Dart
/// sees anything. Native builds are unaffected by CORS — this is purely a web
/// constraint.
///
/// So the app keeps one routing setting. Native defaults to [NetMode.direct];
/// web defaults to a wrapping proxy, and the user can change or clear it in
/// Настройки.
class Net {
  const Net._();

  static const String _key = 'dramix.net';
  static const String _backendKey = 'dramix.backend.origin';
  static Uri? _backendOrigin;

  /// Optional owned catalog server. Provider credentials never leave the server.
  static Uri? get backendOrigin => _backendOrigin;

  static Uri validateBackendOrigin(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority || uri.host.isEmpty ||
        uri.port < 1 || uri.port > 65535 ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                const {'localhost', '127.0.0.1', '::1'}.contains(uri.host)))) {
      throw const FormatException(
          'Укажите HTTPS-адрес сервера без пути, параметров и пароля');
    }
    return uri.replace(path: '');
  }

  static Future<void> setBackend(String? value) async {
    final origin = value == null || value.trim().isEmpty
        ? null
        : validateBackendOrigin(value);
    final prefs = await SharedPreferences.getInstance();
    if (origin == null) {
      await prefs.remove(_backendKey);
    } else {
      await prefs.setString(_backendKey, origin.toString());
    }
    _backendOrigin = origin;
    revision.value++;
  }

  /// Publicly reachable proxy used by default on web. It genuinely echoes the
  /// caller's origin in `Access-Control-Allow-Origin` (verified).
  static const String allOrigins = 'https://api.allorigins.win/get?url=';

  /// Bumped when routing changes so open screens can retry.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static NetMode _mode = kIsWeb ? NetMode.wrap : NetMode.direct;
  static String _template = allOrigins;

  static NetMode get mode => _mode;
  static String get template => _template;
  static bool get isDirect => _mode == NetMode.direct;

  /// Web must proxy; native must not.
  static NetMode get defaultMode => kIsWeb ? NetMode.wrap : NetMode.direct;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apply(prefs.getString(_key));
    final saved = prefs.getString(_backendKey);
    try {
      _backendOrigin = saved == null ? null : validateBackendOrigin(saved);
    } on FormatException {
      _backendOrigin = null;
      await prefs.remove(_backendKey);
    }
  }

  static Future<void> set(
      {required NetMode mode, required String template}) async {
    _mode = mode;
    final trimmed = template.trim();
    _template = trimmed.isEmpty ? allOrigins : trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _encode());
    revision.value++;
  }

  static Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _mode = defaultMode;
    _template = allOrigins;
    revision.value++;
  }

  static void _apply(String? raw) {
    if (raw == null || raw.isEmpty) {
      _mode = defaultMode;
      _template = allOrigins;
      return;
    }
    final parts = raw.split('|');
    _mode = switch (parts.first) {
      'direct' => NetMode.direct,
      'prefix' => NetMode.prefix,
      _ => NetMode.wrap,
    };
    _template = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : allOrigins;
  }

  static String _encode() => '${switch (_mode) {
        NetMode.direct => 'direct',
        NetMode.prefix => 'prefix',
        NetMode.wrap => 'wrap',
      }}|$_template';

  /// A client honouring the current routing. Callers own the instance.
  static http.Client createClient() => _mode == NetMode.direct
      ? http.Client()
      : CorsProxyClient(mode: _mode, template: _template);
}

/// Rewrites every request through a CORS proxy.
class CorsProxyClient extends http.BaseClient {
  CorsProxyClient({
    required this.mode,
    required this.template,
    http.Client? inner,
  }) : _inner = inner ?? http.Client();

  final NetMode mode;
  final String template;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Kodik's endpoints used here are all GETs, and proxies only relay simple
    // requests, so anything else is a programming error worth surfacing.
    if (request.method != 'GET') {
      throw http.ClientException(
          'CORS-прокси поддерживает только GET-запросы', request.url);
    }

    final target = request.url.toString();
    final uri = Uri.parse('$template${Uri.encodeComponent(target)}');
    final response =
        await _inner.get(uri, headers: const {'User-Agent': appUserAgent});

    if (response.statusCode != 200) {
      return http.StreamedResponse(
        Stream<List<int>>.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }

    if (mode == NetMode.prefix) return _json(response.bodyBytes, 200);

    dynamic decoded;
    try {
      decoded =
          jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (_) {
      throw http.ClientException(
          'Прокси вернул некорректный ответ', request.url);
    }
    if (decoded is! Map || decoded['contents'] is! String) {
      throw http.ClientException(
          'Прокси вернул неожиданный формат ответа', request.url);
    }

    // The proxy itself always answers 200, so the upstream status has to be
    // recovered — the 401-retry logic depends on it.
    var code = 200;
    final status = decoded['status'];
    if (status is Map && status['http_code'] is num) {
      code = (status['http_code'] as num).toInt();
    }
    return _json(utf8.encode(decoded['contents'] as String), code);
  }

  @override
  void close() => _inner.close();

  static http.StreamedResponse _json(List<int> bytes, int status) =>
      http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
}
