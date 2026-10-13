import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dramix/core/backend_comments.dart';

void main() {
  test('reads use exact work/season/episode and hide spoilers by default', () async {
    final api = BackendComments(origin: Uri.parse('https://example.test'),
      token: () => null, userId: () => null, client: MockClient((request) async {
        expect(request.url.path, '/v1/comments');
        expect(request.url.queryParameters['work_key'], 'kinopoisk:42');
        expect(request.url.queryParameters['season'], '2');
        expect(request.url.queryParameters['episode'], '3');
        expect(request.url.queryParameters['reveal_spoilers'], 'false');
        expect(request.headers.containsKey('Authorization'), false);
        return http.Response(jsonEncode({'items': [
          {'id': 1, 'author': 'u', 'author_id': 2, 'text': null,
            'spoiler': true, 'deleted': false}
        ], 'cursor': 1, 'has_more': false}), 200);
      }));
    final page = await api.read(workKey: 'kinopoisk:42', season: 2, episode: 3);
    expect(page.items.single.text, isNull);
    expect(page.items.single.spoiler, isTrue);
  });

  test('ambiguous failure retry keeps the exact body and operation key', () async {
    final requests = <http.Request>[];
    final api = BackendComments(origin: Uri.parse('https://example.test'),
      token: () => 'synthetic-session', userId: () => '2',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', requests.length == 1 ? 503 : 200);
      }));
    final operation = api.create(workKey: 'kinopoisk:42', season: 1,
      episode: 2, text: 'test', spoiler: true);
    await expectLater(api.submit(operation), throwsA(isA<CommentsError>()));
    await api.submit(operation);
    expect(requests[0].body, requests[1].body);
    expect(requests[0].headers['Idempotency-Key'],
      requests[1].headers['Idempotency-Key']);
  });

  test('queued operation cannot be replayed as another account', () async {
    String? user = '2';
    int sent = 0;
    final api = BackendComments(origin: Uri.parse('https://example.test'),
      token: () => 'synthetic-session', userId: () => user,
      client: MockClient((request) async { sent++; return http.Response('{}', 200); }));
    final operation = api.create(workKey: 'kinopoisk:42', season: 1,
      episode: 1, text: 'test', spoiler: false);
    user = '3';
    await expectLater(api.submit(operation), throwsA(isA<CommentsError>()));
    expect(sent, 0);
  });

  test('non-author edit and delete never send requests', () {
    final api = BackendComments(origin: Uri.parse('https://example.test'),
      token: () => 'synthetic-session', userId: () => '2',
      client: MockClient((request) async => http.Response('{}', 200)));
    const other = EpisodeComment(id: 1, author: 'other', authorId: '3',
      text: 'text', spoiler: false, deleted: false);
    expect(() => api.edit(other, 'new', false), throwsA(isA<CommentsError>()));
    expect(() => api.delete(other), throwsA(isA<CommentsError>()));
  });

  test('spoiler reveal is explicit and failure messages omit server content', () async {
    final api = BackendComments(origin: Uri.parse('https://example.test'),
      token: () => null, userId: () => null, client: MockClient((request) async {
        expect(request.url.queryParameters['reveal_spoilers'], 'true');
        return http.Response('private server details', 500);
      }));
    try {
      await api.read(workKey: 'kinopoisk:42', season: 1, episode: 1,
        revealSpoilers: true);
      fail('Expected failure');
    } on CommentsError catch (e) {
      expect(e.message, isNot(contains('private')));
    }
  });
}
