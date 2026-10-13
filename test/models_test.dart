import 'package:flutter_test/flutter_test.dart';

import 'package:dramix/core/kodik_token.dart';
import 'package:dramix/core/models.dart';

import 'fixtures.dart';

void main() {
  group('KodikTokenCrypto', () {
    test('round-trips a 32-character token', () {
      final token = '0' * 16 + '1' * 16;
      final encrypted = KodikTokenCrypto.encrypt(token);
      expect(KodikTokenCrypto.decrypt(encrypted), token);
    });

    test('decrypts encoded synthetic candidates into 32 hex characters', () {
      expect(KodikTokenStore.bundledTokens, isEmpty);
      final fixtures = <String>['0' * 32, '1' * 32];
      final candidates = fixtures.map(KodikTokenCrypto.encrypt).toList();
      expect(candidates, hasLength(2));
      for (var i = 0; i < candidates.length; i++) {
        final token = KodikTokenCrypto.decrypt(candidates[i]);
        expect(token, fixtures[i], reason: 'synthetic candidate $i');
        expect(token!.length, 32);
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(token), isTrue);
      }
    });

    test('rejects malformed input instead of throwing', () {
      expect(KodikTokenCrypto.decrypt(null), isNull);
      expect(KodikTokenCrypto.decrypt(''), isNull);
      expect(KodikTokenCrypto.decrypt('abc'), isNull, reason: 'odd length');
      expect(KodikTokenCrypto.decrypt('?' * 48), isNull, reason: 'not base64');
    });
  });

  group('KodikTitle', () {
    test('parses a Korean drama and resolves its label', () {
      final title = KodikTitle.fromJson(vincenzoJson);

      expect(title.id, 'serial-32799');
      expect(title.type, 'foreign-serial');
      expect(title.title, 'Винченцо');
      expect(title.year, 2021);
      expect(title.typeLabel, 'Дорама', reason: 'country is Корея Южная');
      expect(title.isSerial, isTrue);
    });

    test('normalises protocol-relative links to https', () {
      final title = KodikTitle.fromJson(vincenzoJson);
      expect(title.link, startsWith('https://kodikplayer.com/'));
    });

    test('builds an ordered playback list from the season tree', () {
      final refs = KodikTitle.fromJson(vincenzoJson).episodeRefs;

      expect(refs.length, 2);
      expect(refs[0].season, 1);
      expect(refs[0].episode, 1);
      expect(refs[1].episode, 2);
      expect(refs[0].url,
          'https://kodikplayer.com/seria/790235/88a00cf646a66484dd1b1f6b6719ff3a/720p');
      expect(refs[0].label, 'Сезон 1 · Серия 1');
    });

    test('falls back to the top-level link for a single film', () {
      final title = KodikTitle.fromJson(movieJson);

      expect(title.typeLabel, 'Фильм');
      expect(title.isSerial, isFalse);
      expect(title.episodeRefs, hasLength(1));
      expect(title.episodeRefs.single.url,
          'https://kodikplayer.com/video/108152/869f513fbac154c33b73dcce24187bd2/720p');
    });

    test('exposes poster, genre and rating metadata', () {
      final title = KodikTitle.fromJson(vincenzoJson);

      expect(
          title.poster, 'https://st.kp.yandex.net/images/film_big/1398913.jpg');
      expect(title.genres, ['драма', 'комедия', 'криминал']);
      expect(title.material!.bestRating, 8.4);
      expect(title.material!.ratingSource, 'Кинопоиск');
      expect(title.material!.countryLabel, 'Корея Южная');
      expect(title.totalEpisodes, 2,
          reason: 'season tree wins over episodes_count');
    });

    test('labels a US horror film by its type, not country', () {
      final title = KodikTitle.fromJson(movieJson);
      expect(title.typeLabel, 'Фильм');
      expect(title.material!.bestRating, 6.1);
    });

    test('survives a sparse payload', () {
      final title = KodikTitle.fromJson(const {'id': 'x-1'});
      expect(title.id, 'x-1');
      expect(title.title, 'Без названия');
      expect(title.episodeRefs, isEmpty);
      expect(title.poster, isNull);
      expect(title.material, isNull);
    });
  });

  group('KodikPage', () {
    test('reads total, results and the pagination cursor', () {
      final page = KodikPage.fromJson({
        'total': 19721,
        'next_page': 'https://kodik-api.com/list?token=x&next=abc',
        'results': [vincenzoJson],
      });

      expect(page.total, 19721);
      expect(page.results.single.title, 'Винченцо');
      expect(page.hasMore, isTrue);
    });

    test('reports exhaustion when next_page is absent', () {
      final page = KodikPage.fromJson({'total': 1, 'results': []});
      expect(page.hasMore, isFalse);
      expect(page.results, isEmpty);
    });
  });

  group('normalizeLink', () {
    test('handles protocol-relative, http and plain links', () {
      expect(normalizeLink('//host/a'), 'https://host/a');
      expect(normalizeLink('http://host/a'), 'https://host/a');
      expect(normalizeLink('https://host/a'), 'https://host/a');
      expect(normalizeLink(''), '');
      expect(normalizeLink(null), '');
    });
  });

  group('KodikCatalog', () {
    test('covers drama and film types', () {
      expect(KodikCatalog.dramas, contains('foreign-serial'));
      expect(KodikCatalog.movies, contains('foreign-movie'));
      expect(KodikCatalog.all, contains('anime-serial'));
    });
  });
}
