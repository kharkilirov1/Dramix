import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dramix/core/kodik_api.dart';
import 'package:dramix/core/models.dart';

/// Live smoke check against the real Kodik API.
///
/// Deliberately *not* named `*_test.dart`: `flutter test` only auto-discovers
/// that suffix, so a normal run stays offline and deterministic. Run it by
/// naming the file explicitly:
///
///   flutter test test/live_smoke.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // flutter_test installs an HttpOverrides that answers every request with
    // 400; this smoke check needs the real network.
    HttpOverrides.global = null;
  });

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a token resolves and the drama catalog returns data', () async {
    final api = KodikApi();
    final page = await api.browse(types: KodikCatalog.dramas, limit: 6);

    // ignore: avoid_print
    print('token resolved: ${api.tokens.hasToken}');
    // ignore: avoid_print
    print('dramas  : total=${page.total}');
    for (final t in page.results) {
      // ignore: avoid_print
      print('  ${t.id.padRight(18)} ${t.typeLabel.padRight(8)} '
          '${t.title} (${t.year}) rating=${t.material?.bestRating}');
    }

    expect(page.results, isNotEmpty);
    expect(page.total, greaterThan(1000));
    expect(page.hasMore, isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('search finds a drama and its episode links resolve', () async {
    final api = KodikApi();
    final page = await api.search(query: 'Винченцо', limit: 5);

    expect(page.results, isNotEmpty);
    final hit = page.results.first;
    // ignore: avoid_print
    print('hit     : ${hit.title} / ${hit.titleOrig} [${hit.typeLabel}] '
        'year=${hit.year} voice=${hit.translation?.title}');

    final full = await api.byId(hit.id);
    expect(full, isNotNull);

    final refs = full!.episodeRefs;
    // ignore: avoid_print
    print('episodes: ${refs.length}');
    if (refs.isNotEmpty) {
      // ignore: avoid_print
      print('  first : ${refs.first.label} -> ${refs.first.url}');
    }

    expect(refs, isNotEmpty, reason: 'with_episodes must populate seasons');
    expect(refs.first.url, startsWith('https://kodikplayer.com/'));
    expect(full.poster, isNotNull);
    expect(full.material!.bestRating, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('sibling records expose alternative dubbing studios', () async {
    final api = KodikApi();
    final page = await api.search(query: 'Винченцо', limit: 5);
    final versions = await api.versions(page.results.first);

    // ignore: avoid_print
    print('versions: ${versions.length}');
    for (final v in versions.take(8)) {
      // ignore: avoid_print
      print('  ${(v.translation?.title ?? "?").padRight(20)} '
          '${v.totalEpisodes} эп. · ${v.quality}');
    }

    expect(versions, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('films are reachable and carry a playable single link', () async {
    final api = KodikApi();
    final page = await api.browse(types: KodikCatalog.movies, limit: 5);

    expect(page.results, isNotEmpty);
    final film = page.results.first;
    // ignore: avoid_print
    print('film    : ${film.title} [${film.typeLabel}] ${film.year}');

    final full = await api.byId(film.id);
    expect(full, isNotNull);
    expect(full!.link, startsWith('https://kodikplayer.com/'));
    expect(full.episodeRefs, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
