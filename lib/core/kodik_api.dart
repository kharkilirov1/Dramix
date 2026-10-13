import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'kodik_token.dart';
import 'models.dart';
import 'net.dart';

/// Raised for any non-successful Kodik API response.
class KodikApiException implements Exception {
  final int status;
  final String message;
  const KodikApiException(this.status, this.message);
  @override
  String toString() => message;
}

/// Thin, typed client over `kodik-api.com`.
///
/// The token is attached to every request and re-resolved automatically when
/// Kodik answers `401` (revoked token), so long sessions self-heal.
class KodikApi {
  KodikApi({
    KodikTokenStore? tokens,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  })  : tokens = tokens ?? KodikTokenStore(),
        _client = client;

  static final KodikApi instance = KodikApi();

  static const String base = 'https://kodik-api.com';

  final KodikTokenStore tokens;
  final Duration timeout;
  final http.Client? _client;

  final Random _random = Random();

  // ---------------------------------------------------------------- catalog

  /// Browses the catalog with a full [CatalogFilter].
  ///
  /// Pass [cursor] to continue from a previous page's `next_page` URL.
  Future<KodikPage> fetch(
    CatalogFilter filter, {
    String? cursor,
    int limit = 30,
    bool withMaterial = true,
  }) {
    if (cursor != null && cursor.isNotEmpty) return nextPage(cursor);
    return browseFiltered(filter, limit: limit, withMaterial: withMaterial);
  }

  Future<KodikPage> browseFiltered(
    CatalogFilter filter, {
    int limit = 30,
    bool withMaterial = true,
  }) async {
    final uri = Uri.parse('$base/list').replace(queryParameters: <String, String>{
      ...filter.toQuery(),
      'limit': '$limit',
      if (withMaterial) 'with_material_data': 'true',
    });
    return KodikPage.fromJson(_asMap(await _request(uri)));
  }

  /// Convenience wrapper used by tests and simple callers.
  Future<KodikPage> browse({
    String types = KodikCatalog.dramas,
    int limit = 30,
    String sort = 'updated_at',
    String order = 'desc',
    bool withMaterial = true,
    int? year,
  }) =>
      browseFiltered(
        CatalogFilter(
          types: types,
          sort: CatalogSort.values.firstWhere((s) => s.value == sort,
              orElse: () => CatalogSort.updated),
          year: year,
        ),
        limit: limit,
        withMaterial: withMaterial,
      );

  /// Follows a `next_page` link returned by [fetch] or [search].
  Future<KodikPage> nextPage(String url) async {
    final uri = Uri.tryParse(url);
    final origin = Uri.parse(base);
    if (uri == null ||
        uri.scheme != origin.scheme ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path != '/list' && uri.path != '/search')) {
      throw const KodikApiException(-1, 'Некорректная ссылка следующей страницы');
    }
    return KodikPage.fromJson(_asMap(await _request(uri)));
  }

  /// Free-text search. `title` is only honoured by `/search`, not `/list`.
  Future<KodikPage> search({
    required String query,
    String? types,
    int limit = 30,
    int? year,
    String? genres,
    bool withMaterial = true,
    bool strict = false,
  }) async {
    final uri = Uri.parse('$base/search').replace(queryParameters: <String, String>{
      'title': query,
      'limit': '$limit',
      if (types != null && types.isNotEmpty) 'types': types,
      if (year != null) 'year': '$year',
      if (genres != null && genres.isNotEmpty) 'genres': genres,
      if (strict) 'strict': 'true',
      if (withMaterial) 'with_material_data': 'true',
    });
    return KodikPage.fromJson(_asMap(await _request(uri)));
  }

  /// Fetches one title with its full season/episode tree.
  Future<KodikTitle?> byId(String id) async {
    final uri = Uri.parse('$base/search').replace(queryParameters: <String, String>{
      'id': id,
      'limit': '1',
      'with_material_data': 'true',
      'with_episodes': 'true',
    });
    final page = KodikPage.fromJson(_asMap(await _request(uri)));
    return page.results.isEmpty ? null : page.results.first;
  }

  /// All dubbing/subtitle variants of the same content.
  ///
  /// Kodik stores each translation as a separate entry, so we look the title up
  /// by its external id (Kinopoisk → IMDb → MyDramaList) and filter unrelated
  /// hits out.
  Future<List<KodikTitle>> versions(KodikTitle source) async {
    final params = <String, String>{
      'limit': '50',
      'with_material_data': 'true',
      'with_episodes': 'true',
    };
    final kp = source.kinopoiskId;
    final imdb = source.imdbId;
    final mdl = source.mdlId;
    if (kp != null && kp.isNotEmpty) {
      params['kinopoisk_id'] = kp;
    } else if (imdb != null && imdb.isNotEmpty) {
      params['imdb_id'] = imdb;
    } else if (mdl != null && mdl.isNotEmpty) {
      params['mdl_id'] = mdl;
    } else {
      return <KodikTitle>[source];
    }

    final page =
        KodikPage.fromJson(_asMap(await _request(Uri.parse('$base/search').replace(
      queryParameters: params,
    ))));
    final same = page.results
        .where((t) =>
            t.year == null || source.year == null || t.year == source.year)
        .toList();
    if (same.isEmpty) return <KodikTitle>[source];
    same.sort((a, b) => (b.totalEpisodes ?? 0).compareTo(a.totalEpisodes ?? 0));
    return same;
  }

  /// A random title, used by the Обзор "Рандом" tile.
  ///
  /// Kodik has no random endpoint, so this varies type, genre and year until a
  /// page comes back non-empty.
  Future<KodikTitle?> randomTitle() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final filter = CatalogFilter(
        types: KodikCatalog.all,
        year: _random.nextBool() ? 1990 + _random.nextInt(37) : null,
        genres: <String>{DramaGenres.all[_random.nextInt(DramaGenres.all.length)]},
        sort: CatalogSort.rating,
      );
      final page = await browseFiltered(filter, limit: 20);
      if (page.results.isNotEmpty) {
        return page.results[_random.nextInt(page.results.length)];
      }
    }
    return null;
  }

  /// Every dubbing studio known to Kodik (3251 voice + 381 subtitle tracks).
  Future<List<KodikTranslation>> translations() async {
    final json = await _request(Uri.parse('$base/translations'));
    if (json is! List) return const <KodikTranslation>[];
    return json
        .whereType<Map>()
        .map((e) => KodikTranslation.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // -------------------------------------------------------------- utilities

  /// Collapses Kodik's per-dubbing duplicates, preserving order.
  static List<KodikTitle> dedupe(Iterable<KodikTitle> items) {
    final seen = <String>{};
    final out = <KodikTitle>[];
    for (final item in items) {
      if (seen.add(item.dedupeKey)) out.add(item);
    }
    return out;
  }

  // ------------------------------------------------------------------ plumbing

  static Map<String, dynamic> _asMap(dynamic json) {
    if (json is Map<String, dynamic>) return json;
    if (json is Map) return json.cast<String, dynamic>();
    throw const KodikApiException(-1, 'Некорректный ответ Kodik');
  }

  Future<dynamic> _request(Uri uri, {bool retry = true}) async {
    final token = await tokens.ensure();
    final resp = await _send(_withToken(uri, token));

    if (resp.statusCode == 401) {
      // Remember every rejection, including a failed replacement token.
      await tokens.invalidate(rejected: token);
      if (retry) return _request(uri, retry: false);
    }
    if (resp.statusCode != 200) {
      throw KodikApiException(resp.statusCode, _describe(resp));
    }

    final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const KodikApiException(-1, 'Некорректный ответ Kodik');
    }
  }

  static Uri _withToken(Uri uri, String token) {
    final q = Map<String, String>.from(uri.queryParameters);
    q['token'] = token;
    return uri.replace(queryParameters: q);
  }

  static String _describe(http.Response resp) {
    try {
      final decoded =
          jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // fall through to the generic message
    }
    if (resp.statusCode == 401) return 'Токен Kodik отклонён';
    if (resp.statusCode == 400) return 'Kodik отклонил запрос';
    if (resp.statusCode == 404) return 'Ничего не найдено';
    return 'Ошибка Kodik (HTTP ${resp.statusCode})';
  }

  Future<http.Response> _send(Uri uri) async {
    final client = _client ?? Net.createClient();
    try {
      return await client
          .get(uri, headers: const <String, String>{
            'User-Agent': appUserAgent,
            'Accept': 'application/json',
          })
          .timeout(timeout);
    } finally {
      if (_client == null) client.close();
    }
  }
}
