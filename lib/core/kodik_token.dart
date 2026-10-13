import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'net.dart';

/// Kodik gatekeeps its API: every call needs `?token=<32 hex chars>`, and no
/// public signup exists. The community maintains a pool of working tokens that
/// is rotated as Kodik revokes them, and the pool is published obfuscated so
/// search engines do not index it.
///
/// This class implements that obfuscation scheme so the app can carry a few
/// defaults and refresh them at runtime.
class KodikTokenCrypto {
  const KodikTokenCrypto._();

  static String _reverse(String s) =>
      String.fromCharCodes(s.codeUnits.reversed);

  static String? _decodeChunk(String chunk) {
    if (chunk.isEmpty) return null;
    try {
      return utf8
          .decode(base64.decode(chunk + '=' * ((4 - chunk.length % 4) % 4)));
    } catch (_) {
      return null;
    }
  }

  /// Decodes `reverse(b64(secondHalf)) + reverse(b64(firstHalf))`.
  static String? decrypt(String? obfuscated) {
    final s = (obfuscated ?? '').trim();
    if (s.length < 2 || s.length.isOdd) return null;
    final n = s.length ~/ 2;
    final first = _decodeChunk(_reverse(s.substring(n)));
    final second = _decodeChunk(_reverse(s.substring(0, n)));
    if (first == null || second == null) return null;
    return first + second;
  }

  /// Inverse of [decrypt]. Kept for round-trip tests and tooling.
  static String encrypt(String token) {
    if (token.isEmpty) return '';
    final mid = token.length ~/ 2;
    final a = _reverse(base64.encode(utf8.encode(token.substring(0, mid))));
    final b = _reverse(base64.encode(utf8.encode(token.substring(mid))));
    return b + a;
  }
}

/// Thrown when no usable Kodik token could be found.
class KodikTokenException implements Exception {
  final String message;
  const KodikTokenException(this.message);
  @override
  String toString() => message;
}

/// Resolves a working Kodik API token, in priority order:
///
/// 1. the token that already worked in this session,
/// 2. the last token that passed validation (cached),
/// 3. a token the user pasted in Settings,
/// 4. explicitly supplied obfuscated candidates (none by default),
/// 5. a freshly downloaded community pool.
///
/// Every candidate is validated against the live API before being accepted,
/// so a revoked token never reaches the rest of the app.
class KodikTokenStore {
  KodikTokenStore({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.candidates = bundledTokens,
  }) : _client = client;

  static const String apiBase = 'https://kodik-api.com';
  static const String communityTokensUrl =
      'https://raw.githubusercontent.com/YaNesyTortiK/AnimeParsers/'
      'main/kdk_tokns/tokens.json';

  static const String _cacheKey = 'kodik.token.cache';
  static const String _userKey = 'kodik.token.user';

  /// Published source does not embed API credentials.
  static const List<String> bundledTokens = <String>[];

  /// Bumped whenever the active token changes, so screens can react.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final http.Client? _client;
  final Duration timeout;

  /// Optional token candidates, obfuscated with [KodikTokenCrypto.encrypt].
  final List<String> candidates;

  String? _token;

  /// Tokens the API refused during this session; never offered again.
  final Set<String> _rejected = <String>{};

  String? get token => _token;
  bool get hasToken => (_token ?? '').isNotEmpty;

  /// Returns a validated token, resolving one if necessary.
  Future<String> ensure({bool forceRefresh = false}) async {
    if (!forceRefresh && hasToken) return _token!;

    final prefs = await SharedPreferences.getInstance();

    if (!forceRefresh) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null &&
          !_rejected.contains(cached) &&
          await validate(cached)) {
        return _accept(cached, prefs, persist: false);
      }

      final user = (prefs.getString(_userKey) ?? '').trim();
      if (user.isNotEmpty && await validate(user)) {
        return _accept(user, prefs, persist: false);
      }
    }

    for (final obfuscated in candidates) {
      final candidate = KodikTokenCrypto.decrypt(obfuscated);
      if (candidate != null &&
          !_rejected.contains(candidate) &&
          await validate(candidate)) {
        return _accept(candidate, prefs);
      }
    }

    for (final candidate in await _fetchCommunityTokens()) {
      if (!_rejected.contains(candidate) && await validate(candidate)) {
        return _accept(candidate, prefs);
      }
    }

    throw const KodikTokenException(
      'Не удалось получить рабочий токен Kodik. '
      'Добавьте свой токен в настройках.',
    );
  }

  /// Drops the in-memory token so the next [ensure] re-resolves.
  ///
  /// [rejected] records a token the API just refused so re-resolution does not
  /// hand the same broken token straight back.
  Future<void> invalidate({String? rejected}) async {
    if (rejected != null && rejected.isNotEmpty) _rejected.add(rejected);
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  /// Checks a candidate against the live API with a minimal request.
  Future<bool> validate(String candidate) async {
    if (candidate.trim().isEmpty) return false;
    try {
      final uri = Uri.parse('$apiBase/search').replace(queryParameters: {
        'token': candidate.trim(),
        'title': 'a',
        'limit': '1',
      });
      final resp = await _get(uri);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> userToken() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(_userKey) ?? '').trim();
    return raw.isEmpty ? null : raw;
  }

  /// Stores (or clears) a user-supplied token.
  Future<bool> setUserToken(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_userKey);
      await invalidate();
      return false;
    }
    if (!await validate(trimmed)) return false;
    await prefs.setString(_userKey, trimmed);
    await _accept(trimmed, prefs);
    return true;
  }

  Future<String> _accept(String value, SharedPreferences prefs,
      {bool persist = true}) async {
    _token = value;
    _rejected.remove(value);
    if (persist) await prefs.setString(_cacheKey, value);
    revision.value++;
    return value;
  }

  Future<List<String>> _fetchCommunityTokens() async {
    try {
      final resp = await _get(Uri.parse(communityTokensUrl));
      if (resp.statusCode != 200) return const [];
      final decoded =
          jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (decoded is! Map) return const [];
      final out = <String>[];
      for (final section in const ['stable', 'unstable', 'legacy']) {
        final list = decoded[section];
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map) continue;
          final candidate = KodikTokenCrypto.decrypt(item['tokn'] as String?);
          if (candidate != null && !out.contains(candidate)) out.add(candidate);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<http.Response> _get(Uri uri) async {
    final client = _client ?? Net.createClient();
    try {
      return await client.get(uri,
          headers: const {'User-Agent': appUserAgent}).timeout(timeout);
    } finally {
      if (_client == null) client.close();
    }
  }
}
