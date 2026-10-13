import 'dart:convert';
import 'package:http/http.dart' as http;

/// Backend sessions are deliberately memory-only. Guest storage is untouched.
class BackendError implements Exception {
  final int status;
  final String message;
  const BackendError(this.status, this.message);
  @override
  String toString() => message;
}

class BackendConflict extends BackendError {
  final String workKey;
  const BackendConflict(this.workKey)
      : super(409, 'Конфликт данных для $workKey. Обновите облачные данные; автоматическая перезапись отключена.');
}

class BackendSession {
  static BackendSession? _current;
  static BackendSession? get current => _current;
  /// Changing server destroys the previous in-memory session before reuse.
  static BackendSession forOrigin(Uri origin) {
    if (_current?.origin != origin) {
      _current?.close();
      _current = BackendSession(origin);
    }
    return _current!;
  }
  final Uri origin;
  final http.Client client;
  String? _token;
  String? userId;
  String? username;
  DateTime? expiresAt;
  BackendSession(this.origin, {http.Client? client})
      : client = client ?? http.Client() {
    if (origin.host.isEmpty || origin.userInfo.isNotEmpty ||
        origin.query.isNotEmpty || origin.fragment.isNotEmpty ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        (origin.scheme != 'https' &&
          !(origin.scheme == 'http' &&
            ['localhost', '127.0.0.1', '::1'].contains(origin.host)))) {
      throw ArgumentError('Use HTTPS or a local loopback backend origin');
    }
  }
  String? get token => authenticated ? _token : null;
  bool get authenticated => _token != null && userId != null &&
      expiresAt != null && expiresAt!.isAfter(DateTime.now());
  Future<Map<String, dynamic>> request(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query,
       String? operationKey, bool auth = true}) async {
    if (auth && !authenticated) {
      throw const BackendError(401, 'Войдите в аккаунт сервера.');
    }
    final req = http.Request(method, origin.replace(path: path, queryParameters: query));
    req.followRedirects = false;
    req.headers['Accept'] = 'application/json';
    if (auth) req.headers['Authorization'] = 'Bearer $_token';
    if (operationKey != null) req.headers['Idempotency-Key'] = operationKey;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 15)))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && auth) _clear();
      // Do not display upstream bodies which might contain private information.
      throw BackendError(response.statusCode,
          'Ошибка сервера (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid backend response');
    return decoded.cast<String, dynamic>();
  }
  Future<void> signIn(String name, String password, {bool register = false}) async {
    final result = await request('POST',
        register ? '/v1/auth/register' : '/v1/auth/login',
        body: {'username': name.trim(), 'password': password}, auth: false);
    if (result['token'] is! String || result['user_id'] is! String ||
        result['expires_at'] is! num) {
      throw const FormatException('Invalid session response');
    }
    _token = result['token'] as String;
    userId = result['user_id'] as String;
    username = name.trim();
    expiresAt = DateTime.fromMillisecondsSinceEpoch(
        ((result['expires_at'] as num) * 1000).round());
  }
  Future<void> logout() async {
    try {
      if (authenticated) await request('POST', '/v1/auth/logout', body: {});
    } finally {
      _clear();
    }
  }
  void _clear() { _token = null; userId = null; username = null; expiresAt = null; }
  void close() { _clear(); client.close(); }
}
