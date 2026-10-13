import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/backend_session.dart';
import '../lib/core/backend_sync.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('rejects credentials, non-local http and paths in backend origin', () {
    for (final value in ['http://example.com', 'https://user:pass@example.com',
      'https://example.com/path', 'https://example.com?token=x']) {
      expect(() => BackendSession(Uri.parse(value)), throwsArgumentError);
    }
  });
  test('session stays memory-only and logout clears even when server fails', () async {
    final session = BackendSession(Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/logout')) return http.Response('{}', 503);
        return http.Response(jsonEncode({'token': 'fixture-token', 'user_id': 'a',
          'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch / 1000}), 200);
      }));
    await session.signIn('tester', 'fixture-password');
    expect(session.authenticated, isTrue);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    await expectLater(session.logout(), throwsA(isA<BackendError>()));
    expect(session.authenticated, isFalse);
    expect(session.token, isNull);
    session.close();
  });
  test('pull paginates both feeds and preserves tombstones and guest keys', () async {
    SharedPreferences.setMockInitialValues({'dramix.history': <String>['guest']});
    final calls = <String>[];
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        if (request.url.path.contains('/auth/')) return http.Response(jsonEncode({
          'token': 'fixture-token', 'user_id': 'a',
          'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch / 1000}), 200);
        calls.add('${request.url.path}?${request.url.query}');
        final first = request.url.queryParameters['after'] == '0';
        return http.Response(jsonEncode({
          'items': first ? [{'work_key': 'kodik:1', 'revision': 1, 'deleted': true,
            'season': 1, 'episode': 1, 'data': {}}] : [],
          'cursor': first ? 1 : 2, 'has_more': first,
        }), 200);
      }));
    await session.signIn('tester', 'fixture-password');
    final snapshot = await BackendSync(session).pull();
    expect(calls.length, 4);
    expect((snapshot['library'] as Map)['kodik:1']['deleted'], isTrue);
    expect((await SharedPreferences.getInstance()).getStringList('dramix.history'), ['guest']);
    session.close();
  });
  test('409 preserves exact pending operation and guest backup for retry', () async {
    final requests = <String>[];
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        if (request.url.path.contains('/auth/')) return http.Response(jsonEncode({
          'token': 'fixture-token', 'user_id': 'a',
          'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch / 1000}), 200);
        requests.add('${request.headers['Idempotency-Key']}:${request.body}');
        return http.Response('{}', 409);
      }));
    await session.signIn('tester', 'fixture-password');
    final scope = 'dramix.cloud.v1.${Uri.encodeComponent(session.origin.toString())}.a';
    final prefs = await SharedPreferences.getInstance();
    final pending = jsonEncode([{'key': 'fixture-operation-01',
      'body': {'work_key': 'kodik:7', 'base_revision': 0, 'favorite': true}}]);
    await prefs.setString('$scope.pending', pending);
    await prefs.setString('dramix.ratings', '{"kodik:7":4}');
    final sync = BackendSync(session);
    for (var i = 0; i < 2; i++) {
      await expectLater(sync.retryPending(), throwsA(isA<BackendConflict>()));
    }
    expect(requests[0], requests[1]);
    expect(prefs.getString('$scope.pending'), pending);
    expect(prefs.getString('dramix.ratings'), '{"kodik:7":4}');
    session.close();
  });

  Map<String, dynamic> credentials(String user) => {
    'token': 'token-$user', 'user_id': user,
    'expires_at': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch / 1000,
  };

  test('late old 401 cannot clear a newly signed-in account', () async {
    final oldResponse = Completer<http.Response>();
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          final name = (jsonDecode(request.body) as Map)['username'] as String;
          return http.Response(jsonEncode(credentials(name)), 200);
        }
        expect(request.headers['Authorization'], 'Bearer token-a');
        return oldResponse.future;
      }));
    await session.signIn('a', 'fixture-password');
    final oldRequest = session.request('GET', '/v1/library');
    final assertion = expectLater(oldRequest, throwsStateError);
    await session.signIn('b', 'fixture-password');
    oldResponse.complete(http.Response('{}', 401));
    await assertion;
    expect(session.userId, 'b');
    expect(session.token, 'token-b');
    session.close();
  });

  test('older sign-in completion cannot overwrite newer sign-in', () async {
    final delayed = Completer<http.Response>();
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        final name = (jsonDecode(request.body) as Map)['username'] as String;
        if (name == 'a') return delayed.future;
        return http.Response(jsonEncode(credentials(name)), 200);
      }));
    final first = session.signIn('a', 'fixture-password');
    final assertion = expectLater(first, throwsStateError);
    await session.signIn('b', 'fixture-password');
    delayed.complete(http.Response(jsonEncode(credentials('a')), 200));
    await assertion;
    expect(session.userId, 'b');
    session.close();
  });

  test('account change while retry awaits preferences prevents PATCH', () async {
    var patches = 0;
    final session = BackendSession(Uri.parse('http://localhost:8080'),
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          patches++;
          return http.Response('{}', 200);
        }
        final name = (jsonDecode(request.body) as Map)['username'] as String;
        return http.Response(jsonEncode(credentials(name)), 200);
      }));
    await session.signIn('a', 'fixture-password');
    final prefs = await SharedPreferences.getInstance();
    final scope = 'dramix.cloud.v1.${Uri.encodeComponent(session.origin.toString())}.a';
    final pending = jsonEncode([{'key': 'fixture-operation-01',
      'body': {'work_key': 'kodik:7', 'base_revision': 0, 'favorite': true}}]);
    await prefs.setString('$scope.pending', pending);
    final retry = BackendSync(session).retryPending();
    final assertion = expectLater(retry, throwsA(anyOf(isA<StateError>(), isA<BackendError>())));
    await session.signIn('b', 'fixture-password');
    await assertion;
    expect(patches, 0);
    expect(prefs.getString('$scope.pending'), pending);
    session.close();
  });

  test('IPv6 loopback origin is accepted', () {
    final session = BackendSession(Uri.parse('http://[::1]:8080'));
    session.close();
  });

}
