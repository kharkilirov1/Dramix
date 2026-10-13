import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/kodik_api.dart';
import 'package:dramix/core/kodik_token.dart';
import 'package:dramix/core/models.dart';

import 'fixtures.dart';

/// Kodik's token validation probe omits `with_material_data`; real catalog
/// calls always set it. Tests use that to tell the two apart.
bool isProbe(Uri url) => !url.queryParameters.containsKey('with_material_data');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = '0' * 32;
  final t1 = '1' * 32;
  final candidates = <String>[
    KodikTokenCrypto.encrypt(t0),
    KodikTokenCrypto.encrypt(t1),
  ];

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  KodikApi apiWith(MockClient client) => KodikApi(
        tokens: KodikTokenStore(client: client, candidates: candidates),
        client: client,
      );

  group('KodikTokenStore', () {
    test('accepts the first supplied candidate that validates', () async {
      final probed = <String>[];
      final client = MockClient((req) async {
        final token = req.url.queryParameters['token'] ?? '';
        probed.add(token);
        return token == t1
            ? jsonResponse(const {'total': 0, 'results': []})
            : jsonResponse(const {'error': 'nope'}, 401);
      });

      final store = KodikTokenStore(client: client, candidates: candidates);
      final resolved = await store.ensure();

      expect(resolved, t1);
      expect(probed.first, t0, reason: 'the pool is tried in order');
      expect(probed, contains(t1));
      expect(store.hasToken, isTrue);
    });

    test('throws when nothing validates', () async {
      final client =
          MockClient((_) async => jsonResponse(const {'error': 'no'}, 401));
      final store = KodikTokenStore(client: client, candidates: candidates);

      await expectLater(store.ensure(), throwsA(isA<KodikTokenException>()));
      expect(store.hasToken, isFalse);
    });

    test('accepts a valid user token and rejects a bad one', () async {
      final client = MockClient((req) async {
        final token = req.url.queryParameters['token'];
        return token == t1
            ? jsonResponse(const {'total': 0, 'results': []})
            : jsonResponse(const {'error': 'no'}, 401);
      });
      final store = KodikTokenStore(client: client, candidates: candidates);

      expect(await store.setUserToken(t0), isFalse);
      expect(store.hasToken, isFalse);
      expect(await store.setUserToken(t1), isTrue);
      expect(store.token, t1);
      expect(await store.userToken(), t1);
    });

    test('prefers a cached token over the pool', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'kodik.token.cache': t0,
      });
      final probed = <String>[];
      final client = MockClient((req) async {
        probed.add(req.url.queryParameters['token'] ?? '');
        return jsonResponse(const {'total': 0, 'results': []});
      });

      final store = KodikTokenStore(client: client, candidates: candidates);
      expect(await store.ensure(), t0);
      expect(probed, [t0], reason: 'no need to walk the pool');
    });
  });

  group('KodikApi', () {
    test('search parses a drama page and sends the types filter', () async {
      final client = MockClient((req) async {
        if (isProbe(req.url)) {
          return jsonResponse(const {'total': 0, 'results': []});
        }
        expect(req.url.path, '/search');
        expect(req.url.queryParameters['types'], KodikCatalog.dramas);
        expect(req.url.queryParameters['token'], isNotNull);
        return jsonResponse({
          'total': 1,
          'results': [vincenzoJson],
        });
      });

      final page = await apiWith(client)
          .search(query: 'Винченцо', types: KodikCatalog.dramas);

      expect(page.total, 1);
      expect(page.results.single.title, 'Винченцо');
      expect(page.results.single.typeLabel, 'Дорама');
    });

    test('recovers from a revoked token by resolving another', () async {
      final client = MockClient((req) async {
        final token = req.url.queryParameters['token'];
        if (isProbe(req.url)) {
          final ok = token == t0 || token == t1;
          return ok
              ? jsonResponse(const {'total': 0, 'results': []})
              : jsonResponse(const {'error': 'bad'}, 401);
        }
        if (token == t0) return jsonResponse(const {'error': 'revoked'}, 401);
        if (token == t1) {
          return jsonResponse({
            'total': 1,
            'results': [vincenzoJson],
          });
        }
        return jsonResponse(const {'error': 'bad'}, 401);
      });

      final api = apiWith(client);
      final page = await api.search(query: 'Винченцо');

      expect(page.results.single.title, 'Винченцо');
      expect(api.tokens.token, t1,
          reason: 'the revoked token must not be reused');
    });

    test('browse asks for the drama types with a sort key', () async {
      Uri? browseUrl;
      final client = MockClient((req) async {
        if (!isProbe(req.url)) browseUrl = req.url;
        return jsonResponse(const {'total': 0, 'results': []});
      });

      await apiWith(client).browse(
        types: KodikCatalog.dramas,
        sort: 'updated_at',
        order: 'desc',
      );

      expect(browseUrl, isNotNull);
      expect(browseUrl!.path, '/list');
      expect(browseUrl!.queryParameters['types'], KodikCatalog.dramas);
      expect(browseUrl!.queryParameters['sort'], 'updated_at');
      expect(browseUrl!.queryParameters['limit'], '30');
    });

    test('follows an opaque next_page cursor and swaps in a fresh token',
        () async {
      Uri? cursorUrl;
      final client = MockClient((req) async {
        if (req.url.path == '/list') {
          cursorUrl = req.url;
          return jsonResponse({
            'total': 5,
            'results': [movieJson],
          });
        }
        return jsonResponse(const {'total': 0, 'results': []});
      });

      final page = await apiWith(client)
          .nextPage('https://kodik-api.com/list?token=stale&next=cursor-1');

      expect(page.results.single.title, 'Невеста');
      expect(cursorUrl!.queryParameters['next'], 'cursor-1');
      expect(cursorUrl!.queryParameters['token'], t0,
          reason: 'the stale token in the cursor URL is replaced');
    });

    test('byId requests the full season tree', () async {
      Uri? byIdUrl;
      final client = MockClient((req) async {
        if (req.url.queryParameters.containsKey('with_episodes')) {
          byIdUrl = req.url;
        }
        return jsonResponse({
          'total': 1,
          'results': [vincenzoJson],
        });
      });

      final title = await apiWith(client).byId('serial-32799');

      expect(title!.id, 'serial-32799');
      expect(byIdUrl!.queryParameters['id'], 'serial-32799');
      expect(byIdUrl!.queryParameters['with_episodes'], 'true');
    });

    test('byId returns null when Kodik has no match', () async {
      final client = MockClient((_) async {
        return jsonResponse(const {'total': 0, 'results': []});
      });

      expect(await apiWith(client).byId('serial-none'), isNull);
    });

    test('translations parses the studio list', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/translations') {
          return jsonResponse(const [
            {'id': 639, 'title': 'SoftBox', 'type': 'voice'},
            {'id': 869, 'title': 'Субтитры', 'type': 'subtitles'},
          ]);
        }
        return jsonResponse(const {'total': 0, 'results': []});
      });

      final studios = await apiWith(client).translations();

      expect(studios, hasLength(2));
      expect(studios.first.title, 'SoftBox');
      expect(studios.first.isVoice, isTrue);
      expect(studios.last.isVoice, isFalse);
    });

    test('versions looks the title up by its Kinopoisk id', () async {
      Uri? lookupUrl;
      final client = MockClient((req) async {
        if (req.url.queryParameters.containsKey('kinopoisk_id')) {
          lookupUrl = req.url;
        }
        return jsonResponse({
          'total': 1,
          'results': [vincenzoJson],
        });
      });

      final source = KodikTitle.fromJson(vincenzoJson);
      final versions = await apiWith(client).versions(source);

      expect(lookupUrl!.queryParameters['kinopoisk_id'], '1398913');
      expect(versions, hasLength(1));
    });

    test('versions falls back to the source when it has no external id',
        () async {
      final client = MockClient(
          (_) async => jsonResponse(const {'total': 0, 'results': []}));
      final source = KodikTitle.fromJson(const {'id': 'x-1', 'title': 'X'});

      final versions = await apiWith(client).versions(source);

      expect(versions.single.id, 'x-1');
    });

    test('surfaces the server error message', () async {
      final client = MockClient((req) async {
        if (isProbe(req.url)) {
          return jsonResponse(const {'total': 0, 'results': []});
        }
        return jsonResponse(const {'error': 'Kodik отклонил запрос'}, 400);
      });

      await expectLater(
        apiWith(client).search(query: 'x'),
        throwsA(isA<KodikApiException>().having(
            (KodikApiException e) => e.message,
            'message',
            'Kodik отклонил запрос')),
      );
    });

    test('reports malformed JSON instead of crashing', () async {
      final client = MockClient((req) async {
        if (isProbe(req.url)) {
          return jsonResponse(const {'total': 0, 'results': []});
        }
        return http.Response(
          '<html>not json</html>',
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await expectLater(apiWith(client).search(query: 'x'),
          throwsA(isA<KodikApiException>()));
    });
  });
}
