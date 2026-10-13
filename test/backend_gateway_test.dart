import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/kodik_api.dart';
import 'package:dramix/core/kodik_token.dart';
import 'package:dramix/core/net.dart';

class _NoProviderTokens extends KodikTokenStore {
  @override
  Future<String> ensure({bool forceRefresh = false}) =>
      throw StateError('Gateway must not resolve a provider token');
  @override
  Future<void> invalidate({String? rejected}) =>
      throw StateError('Gateway must not invalidate provider tokens');
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Net.load();
  });

  test('backend origin accepts HTTPS and loopback only, with no secrets', () {
    for (final value in [
      'https://dramix.example',
      'https://dramix.example:8443/',
      'http://localhost:8080',
      'http://127.0.0.1:8080',
      'http://[::1]:8080',
    ]) {
      expect(Net.validateBackendOrigin(value).host, isNotEmpty);
    }
    for (final value in [
      'http://dramix.example', 'https://user:password@dramix.example',
      'https://dramix.example?token=secret', 'https://dramix.example/#fragment',
      'https://dramix.example/v1', '//dramix.example', 'not-a-url',
    ]) {
      expect(() => Net.validateBackendOrigin(value), throwsFormatException);
    }
  });

  test('backend is persisted separately from guest network route', () async {
    await Net.set(mode: NetMode.wrap, template: Net.allOrigins);
    await Net.setBackend('https://dramix.example/');
    await Net.load();
    expect(Net.backendOrigin.toString(), 'https://dramix.example');
    expect(Net.mode, NetMode.wrap);
    await Net.setBackend('');
    expect(Net.backendOrigin, isNull);
    expect(Net.mode, NetMode.wrap);
  });

  test('invalid stored origin is removed without blocking guest startup', () async {
    SharedPreferences.setMockInitialValues({
      'dramix.backend.origin': 'https://user:secret@dramix.example',
    });
    await Net.load();
    expect(Net.backendOrigin, isNull);
    expect((await SharedPreferences.getInstance())
        .getString('dramix.backend.origin'), isNull);
  });

  test('gateway sends no provider credentials and preserves pagination filters',
      () async {
    await Net.setBackend('https://dramix.example');
    await Net.set(mode: NetMode.wrap, template: Net.allOrigins);
    final seen = <Uri>[];
    final client = MockClient((request) async {
      seen.add(request.url);
      expect(request.url.host, 'dramix.example');
      expect(request.url.path, '/v1/catalog/search');
      expect(request.url.queryParameters.containsKey('token'), isFalse);
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.followRedirects, isFalse);
      return _json({
        'total': 0, 'results': [],
        'next_cursor': seen.length == 1 ? 'opaque + cursor' : null,
        'next_page': 'https://untrusted.example/?token=secret',
      });
    });
    final api = KodikApi(tokens: _NoProviderTokens(), client: client);
    final page = await api.search(query: 'Название', types: 'foreign-serial',
        year: 2024, strict: true);
    expect(page.hasMore, isTrue);
    expect(page.nextPage, isNot(contains('secret')));
    final second = await api.nextPage(page.nextPage!);
    expect(second.hasMore, isFalse);
    expect(seen.last.queryParameters['title'], 'Название');
    expect(seen.last.queryParameters['types'], 'foreign-serial');
    expect(seen.last.queryParameters['year'], '2024');
    expect(seen.last.queryParameters['strict'], 'true');
    expect(seen.last.queryParameters['next'], 'opaque + cursor');
  });

  test('gateway translations use the same credential-free route', () async {
    await Net.setBackend('https://dramix.example');
    final api = KodikApi(tokens: _NoProviderTokens(),
        client: MockClient((request) async {
      expect(request.url.path, '/v1/catalog/translations');
      expect(request.url.queryParameters, isEmpty);
      return _json([{'id': 1, 'title': 'Studio', 'type': 'voice'}]);
    }));
    expect((await api.translations()).single.title, 'Studio');
  });

  test('gateway errors never trigger token recovery or direct fallback', () async {
    await Net.setBackend('https://dramix.example');
    for (final status in [401, 302, 503]) {
      var calls = 0;
      final api = KodikApi(tokens: _NoProviderTokens(),
          client: MockClient((_) async {
        calls++;
        return _json({'error': 'Server unavailable'}, status);
      }));
      await expectLater(api.browse(), throwsA(isA<KodikApiException>()
          .having((e) => e.status, 'status', status)));
      expect(calls, 1);
    }
  });

  test('gateway rejects foreign and stale provider pagination URLs before IO',
      () async {
    await Net.setBackend('https://dramix.example');
    final api = KodikApi(tokens: _NoProviderTokens(),
        client: MockClient((_) async => throw StateError('No request expected')));
    for (final url in [
      'https://kodik-api.com/list?next=x',
      'https://other.example/v1/catalog/list?next=x',
      'https://dramix.example:8443/v1/catalog/list?next=x',
      'https://user@dramix.example/v1/catalog/list?next=x',
      'https://dramix.example/v1/catalog/translations?next=x',
    ]) {
      await expectLater(api.nextPage(url), throwsA(isA<KodikApiException>()));
    }
  });

  test('gateway rejects malformed page and cursor responses', () async {
    await Net.setBackend('https://dramix.example');
    for (final body in [
      {'error': 'Denied', 'total': 0, 'results': []},
      {'total': 0, 'results': [], 'next_cursor': 42},
      {'total': 0},
    ]) {
      final api = KodikApi(tokens: _NoProviderTokens(),
          client: MockClient((_) async => _json(body)));
      await expectLater(api.browse(), throwsA(isA<KodikApiException>()));
    }
  });

  test('gateway timeout includes waiting for response headers', () async {
    await Net.setBackend('https://dramix.example');
    final pending = Completer<http.Response>();
    final api = KodikApi(tokens: _NoProviderTokens(),
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => pending.future));
    await expectLater(api.browse(), throwsA(isA<TimeoutException>()));
    pending.complete(_json({'total': 0, 'results': []}));
  });
}
