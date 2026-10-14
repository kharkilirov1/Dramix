/// Data models for the Kodik API wire format.
///
/// Field names follow what `kodik-api.com` actually returns (mixed snake_case
/// and camelCase), verified against live responses for `foreign-serial`,
/// `foreign-movie` and `anime-serial` entries.
library;

/// Content type groups accepted by the `types=` query parameter.
class KodikCatalog {
  const KodikCatalog._();

  static const String dramas = 'foreign-serial,russian-serial';
  static const String movies = 'foreign-movie,russian-movie,multi-part-film';
  static const String anime = 'anime,anime-serial';
  static const String cartoons =
      'cartoon-serial,foreign-cartoon,russian-cartoon,soviet-cartoon';
  static const String documentary = 'documentary-serial';
  static const String all =
      'foreign-serial,russian-serial,foreign-movie,russian-movie,'
      'multi-part-film,anime,anime-serial,cartoon-serial,foreign-cartoon,'
      'russian-cartoon,soviet-cartoon,documentary-serial';
}

/// Turns `//host/path` and `http://host/path` into an `https://` URL.
String normalizeLink(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  if (s.startsWith('//')) return 'https:$s';
  if (s.startsWith('http://')) return 'https://${s.substring(7)}';
  return s;
}

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

List<String> _toStrings(Object? v) =>
    (v is List) ? v.whereType<Object>().map((e) => '$e').toList() : const [];

/// Conservative identity: never merge titles merely by name or year.
String titleWorkId(String providerId, {
  String? kinopoiskId, String? imdbId, String? mdlId, String? shikimoriId,
}) {
  String? positive(String? value) {
    final raw = value?.trim();
    if (raw == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(raw)) return null;
    return raw;
  }
  final kp = positive(kinopoiskId);
  if (kp != null) return 'kinopoisk:$kp';
  final imdb = imdbId?.trim().toLowerCase();
  if (imdb != null && RegExp(r'^tt[0-9]+$').hasMatch(imdb)) return 'imdb:$imdb';
  final mdl = positive(mdlId);
  if (mdl != null) return 'mdl:$mdl';
  final shiki = positive(shikimoriId);
  if (shiki != null) return 'shikimori:$shiki';
  return 'kodik:$providerId';
}

/// A dubbing studio / subtitle track.
class KodikTranslation {
  final int id;
  final String title;
  final String type;

  const KodikTranslation({required this.id, required this.title, this.type = 'voice'});

  bool get isVoice => type == 'voice';

  factory KodikTranslation.fromJson(Map<String, dynamic> j) => KodikTranslation(
        id: _toInt(j['id']) ?? 0,
        title: (j['title'] as String?) ?? 'Без названия',
        type: (j['type'] as String?) ?? 'voice',
      );
}

/// Extra metadata returned when `with_material_data=true`.
class KodikMaterial {
  final String? posterUrl;
  final String? description;
  final String? animeKind;
  final String? allStatus;
  final String? ratingMpaa;
  final List<String> genres;
  final List<String> countries;
  final List<String> actors;
  final List<String> directors;
  final List<String> screenshots;
  final int? duration;
  final int? minimalAge;
  final int? episodesTotal;
  final int? episodesAired;
  final double? kinopoiskRating;
  final double? imdbRating;
  final double? shikimoriRating;
  final int? kinopoiskVotes;
  final int? imdbVotes;

  const KodikMaterial({
    this.posterUrl,
    this.description,
    this.animeKind,
    this.allStatus,
    this.ratingMpaa,
    this.genres = const [],
    this.countries = const [],
    this.actors = const [],
    this.directors = const [],
    this.screenshots = const [],
    this.duration,
    this.minimalAge,
    this.episodesTotal,
    this.episodesAired,
    this.kinopoiskRating,
    this.imdbRating,
    this.shikimoriRating,
    this.kinopoiskVotes,
    this.imdbVotes,
  });

  factory KodikMaterial.fromJson(Map<String, dynamic> j) {
    final genres = _toStrings(j['all_genres']);
    return KodikMaterial(
      posterUrl: normalizeLink(j['poster_url'] as String?),
      description: j['description'] as String?,
      animeKind: j['anime_kind'] as String?,
      allStatus: j['all_status'] as String?,
      ratingMpaa: j['rating_mpaa'] as String?,
      genres: genres.isNotEmpty ? genres : _toStrings(j['genres']),
      countries: _toStrings(j['countries']),
      actors: _toStrings(j['actors']),
      directors: _toStrings(j['directors']),
      screenshots: _toStrings(j['screenshots']).map(normalizeLink).toList(),
      duration: _toInt(j['duration']),
      minimalAge: _toInt(j['minimal_age']),
      episodesTotal: _toInt(j['episodes_total']),
      episodesAired: _toInt(j['episodes_aired']),
      kinopoiskRating: _toDouble(j['kinopoisk_rating']),
      imdbRating: _toDouble(j['imdb_rating']),
      shikimoriRating: _toDouble(j['shikimori_rating']),
      kinopoiskVotes: _toInt(j['kinopoisk_votes']),
      imdbVotes: _toInt(j['imdb_votes']),
    );
  }

  /// Best available score, resolved to a 10-point scale.
  double? get bestRating =>
      kinopoiskRating ?? imdbRating ?? shikimoriRating;

  String? get ratingSource {
    if (kinopoiskRating != null) return 'Кинопоиск';
    if (imdbRating != null) return 'IMDb';
    if (shikimoriRating != null) return 'Shikimori';
    return null;
  }

  String? get countryLabel => countries.isEmpty ? null : countries.join(', ');
}

/// One season of a multi-season title.
class KodikSeason {
  final int number;
  final String link;
  final Map<int, String> episodes;

  const KodikSeason({required this.number, this.link = '', this.episodes = const {}});

  int get episodeCount => episodes.length;

  factory KodikSeason.fromJson(int number, Map<String, dynamic> j) {
    final raw = (j['episodes'] as Map?) ?? const {};
    final eps = <int, String>{};
    raw.forEach((k, v) {
      final n = _toInt(k);
      if (n != null && v is String && v.isNotEmpty) eps[n] = normalizeLink(v);
    });
    return KodikSeason(
      number: number,
      link: normalizeLink(j['link'] as String?),
      episodes: eps,
    );
  }
}

/// A single search result / catalog entry.
class KodikTitle {
  final String id;
  final String type;
  final String title;
  final String? titleOrig;
  final String? otherTitle;
  final int? year;
  final String link;
  final int? episodesCount;
  final int? lastSeason;
  final int? lastEpisode;
  final String? quality;
  final bool camrip;
  final bool lgbt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? kinopoiskId;
  final String? imdbId;
  final String? shikimoriId;
  final String? mdlId;
  final List<String> screenshots;
  final KodikTranslation? translation;
  final KodikMaterial? material;
  final Map<int, KodikSeason> seasons;

  const KodikTitle({
    required this.id,
    required this.type,
    required this.title,
    this.titleOrig,
    this.otherTitle,
    this.year,
    this.link = '',
    this.episodesCount,
    this.lastSeason,
    this.lastEpisode,
    this.quality,
    this.camrip = false,
    this.lgbt = false,
    this.createdAt,
    this.updatedAt,
    this.kinopoiskId,
    this.imdbId,
    this.shikimoriId,
    this.mdlId,
    this.screenshots = const [],
    this.translation,
    this.material,
    this.seasons = const {},
  });

  factory KodikTitle.fromJson(Map<String, dynamic> j) {
    final rawSeasons = (j['seasons'] as Map?) ?? const {};
    final seasons = <int, KodikSeason>{};
    rawSeasons.forEach((k, v) {
      final n = _toInt(k);
      if (n != null && v is Map) {
        seasons[n] = KodikSeason.fromJson(n, v.cast<String, dynamic>());
      }
    });
    return KodikTitle(
      id: (j['id'] as String?) ?? '',
      type: (j['type'] as String?) ?? '',
      title: (j['title'] as String?) ?? 'Без названия',
      titleOrig: j['title_orig'] as String?,
      otherTitle: j['other_title'] as String?,
      year: _toInt(j['year']),
      link: normalizeLink(j['link'] as String?),
      episodesCount: _toInt(j['episodes_count']),
      lastSeason: _toInt(j['last_season']),
      lastEpisode: _toInt(j['last_episode']),
      quality: j['quality'] as String?,
      camrip: j['camrip'] == true,
      lgbt: j['lgbt'] == true,
      createdAt: DateTime.tryParse((j['created_at'] as String?) ?? ''),
      updatedAt: DateTime.tryParse((j['updated_at'] as String?) ?? ''),
      kinopoiskId: j['kinopoisk_id']?.toString(),
      imdbId: j['imdb_id'] as String?,
      shikimoriId: j['shikimori_id']?.toString(),
      mdlId: j['mdl_id'] as String?,
      screenshots: _toStrings(j['screenshots']).map(normalizeLink).toList(),
      translation: j['translation'] is Map
          ? KodikTranslation.fromJson(
              (j['translation'] as Map).cast<String, dynamic>())
          : null,
      material: j['material_data'] is Map
          ? KodikMaterial.fromJson(
              (j['material_data'] as Map).cast<String, dynamic>())
          : null,
      seasons: seasons,
    );
  }

  String? get poster => material?.posterUrl;

  List<String> get genres => material?.genres ?? const [];

  /// Alias used by the shared list widgets and the filter screen.
  List<String> get genreList => genres;

  String? get description => material?.description;

  bool get isSerial => type.contains('serial') || type == 'multi-part-film';

  int? get totalEpisodes {
    if (seasons.isNotEmpty) {
      final sum = seasons.values.fold<int>(0, (a, s) => a + s.episodeCount);
      if (sum > 0) return sum;
    }
    return episodesCount ?? material?.episodesTotal;
  }

  /// Human label for the content type, refined by country for dramas.
  String get typeLabel {
    switch (type) {
      case 'foreign-serial':
        return _isKorean ? 'Дорама' : 'Сериал';
      case 'russian-serial':
        return 'Русский сериал';
      case 'foreign-movie':
        return 'Фильм';
      case 'russian-movie':
        return 'Русский фильм';
      case 'multi-part-film':
        return 'Многосерийный фильм';
      case 'anime':
        return 'Аниме-фильм';
      case 'anime-serial':
        return 'Аниме-сериал';
      case 'cartoon-serial':
        return 'Мультсериал';
      case 'foreign-cartoon':
      case 'russian-cartoon':
        return 'Мультфильм';
      case 'soviet-cartoon':
        return 'Советский мультфильм';
      case 'documentary-serial':
        return 'Документальный';
      default:
        return 'Видео';
    }
  }

  bool get _isKorean {
    final c = material?.countries ?? const <String>[];
    return c.any((e) => e.contains('Корея'));
  }

  String get episodesLabel {
    final t = totalEpisodes;
    if (t == null || t <= 0) return isSerial ? '' : 'Фильм';
    return '$t ${_plural(t, 'серия', 'серии', 'серий')}';
  }

  String get subtitle {
    final parts = <String>[];
    if (year != null) parts.add('$year');
    final label = episodesLabel;
    if (label.isNotEmpty) parts.add(label);
    if (translation != null) parts.add(translation!.title);
    return parts.join(' · ');
  }

  /// Flattened, ordered playback list built from [seasons].
  ///
  /// Single films expose only the top-level `link`, so they yield one entry.
  List<KodikEpisodeRef> get episodeRefs {
    final out = <KodikEpisodeRef>[];
    final seasonKeys = seasons.keys.toList()..sort();
    for (final key in seasonKeys) {
      final season = seasons[key]!;
      final numbers = season.episodes.keys.toList()..sort();
      for (final number in numbers) {
        out.add(KodikEpisodeRef(
          season: key,
          episode: number,
          url: season.episodes[number]!,
        ));
      }
    }
    if (out.isEmpty && link.isNotEmpty) {
      out.add(KodikEpisodeRef(season: 1, episode: 1, url: link));
    }
    return out;
  }

  SavedTitleRef get ref => SavedTitleRef(
        id: id,
        title: title,
        poster: poster,
        type: type,
        year: year,
        episodes: totalEpisodes,
        link: link,
        kinopoiskId: kinopoiskId,
        imdbId: imdbId,
        mdlId: mdlId,
        shikimoriId: shikimoriId,
        translationId: translation?.id,
      );

  /// Identity used to collapse Kodik's per-dubbing duplicates in lists.
  ///
  /// Kodik stores every voice-over studio as its own record, so a popular drama
  /// can appear five times in a row. Anything that renders a feed must dedupe.
  String get workId => titleWorkId(id, kinopoiskId: kinopoiskId,
      imdbId: imdbId, mdlId: mdlId, shikimoriId: shikimoriId);

  String get dedupeKey => workId;

  // View aliases that let the shared card widgets stay identical to the
  // reference client's.
  String get titleRu => title;
  String? get image => poster;
  double? get grade => material?.bestRating;
  String get statusName => material?.allStatus ?? '';

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }
}

/// One page of results. Kodik paginates with an opaque `next_page` URL.
class KodikPage {
  final int total;
  final List<KodikTitle> results;
  final String? nextPage;

  const KodikPage({required this.total, required this.results, this.nextPage});

  static const KodikPage empty = KodikPage(total: 0, results: []);

  bool get hasMore => (nextPage ?? '').isNotEmpty;

  factory KodikPage.fromJson(Map<String, dynamic> j) => KodikPage(
        total: _toInt(j['total']) ?? 0,
        results: ((j['results'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => KodikTitle.fromJson(e.cast<String, dynamic>()))
            .toList(),
        nextPage: j['next_page'] as String?,
      );
}

/// One playable episode resolved from a title's season tree.
class KodikEpisodeRef {
  final int season;
  final int episode;
  final String url;

  const KodikEpisodeRef({
    required this.season,
    required this.episode,
    required this.url,
  });

  String get label => 'Сезон $season · Серия $episode';
}

/// Plain snapshot of a title used for offline lists (history, favourites).
class SavedTitleRef {
  final String id;
  final String title;
  final String? poster;
  final String type;
  final int? year;
  final int? episodes;
  final String link;
  final String? kinopoiskId;
  final String? imdbId;
  final String? mdlId;
  final String? shikimoriId;
  final int? translationId;

  String get workId => titleWorkId(id, kinopoiskId: kinopoiskId,
      imdbId: imdbId, mdlId: mdlId, shikimoriId: shikimoriId);

  const SavedTitleRef({
    required this.id,
    required this.title,
    this.poster,
    this.type = '',
    this.year,
    this.episodes,
    this.link = '',
    this.kinopoiskId,
    this.imdbId,
    this.mdlId,
    this.shikimoriId,
    this.translationId,
  });

  String get subtitle {
    final parts = <String>[];
    if (year != null) parts.add('$year');
    if (episodes != null && episodes! > 0) parts.add('$episodes эп.');
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (poster != null) 'poster': poster,
        'type': type,
        if (year != null) 'year': year,
        if (episodes != null) 'episodes': episodes,
        'link': link,
        if (kinopoiskId != null) 'kinopoiskId': kinopoiskId,
        if (imdbId != null) 'imdbId': imdbId,
        if (mdlId != null) 'mdlId': mdlId,
        if (shikimoriId != null) 'shikimoriId': shikimoriId,
        if (translationId != null) 'translationId': translationId,
      };

  factory SavedTitleRef.fromJson(Map<String, dynamic> j) => SavedTitleRef(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? 'Без названия',
        poster: j['poster'] as String?,
        type: (j['type'] as String?) ?? '',
        year: (j['year'] as num?)?.toInt(),
        episodes: (j['episodes'] as num?)?.toInt(),
        link: (j['link'] as String?) ?? '',
        kinopoiskId: j['kinopoiskId'] as String?,
        imdbId: j['imdbId'] as String?,
        mdlId: j['mdlId'] as String?,
        shikimoriId: j['shikimoriId'] as String?,
        translationId: (j['translationId'] as num?)?.toInt(),
      );
}

/// Genre names Kodik actually recognises for `genres=`.
///
/// Verified against the live API: names outside this list silently return zero
/// results, so the filter screen must only offer these.
class DramaGenres {
  const DramaGenres._();

  static const List<String> all = <String>[
    'мелодрама',
    'драма',
    'комедия',
    'фэнтези',
    'детектив',
    'криминал',
    'триллер',
    'боевик',
    'фантастика',
    'приключения',
    'ужасы',
    'мультфильм',
    'военный',
    'семейный',
    'биография',
    'документальный',
    'мюзикл',
    'вестерн',
    'короткометражка',
    'аниме',
  ];
}

/// Countries Kodik recognises for `countries=`.
class DramaCountries {
  const DramaCountries._();

  static const List<String> all = <String>[
    'Корея Южная',
    'Китай',
    'Япония',
    'Турция',
    'Таиланд',
    'США',
  ];
}

/// Airing status accepted by `all_status=`.
enum AiringStatus {
  ongoing('ongoing', 'Онгоинги'),
  released('released', 'Завершенные'),
  anons('anons', 'Анонсы');

  const AiringStatus(this.value, this.label);

  final String value;
  final String label;
}

/// Sort keys accepted by `sort=`.
enum CatalogSort {
  updated('updated_at', 'По дате обновления'),
  rating('kinopoisk_rating', 'По оценке Кинопоиска'),
  imdb('imdb_rating', 'По оценке IMDb'),
  shikimori('shikimori_rating', 'По оценке Shikimori'),
  year('year', 'По году'),
  created('created_at', 'По добавлению');

  const CatalogSort(this.value, this.label);

  final String value;
  final String label;
}

/// Catalog query, mirroring the Anixart filter screen but backed by the
/// parameters Kodik supports.
class CatalogFilter {
  CatalogFilter({
    this.types = KodikCatalog.dramas,
    this.allStatus,
    Set<String>? genres,
    Set<String>? countries,
    this.year,
    this.minimalAge,
    this.minRating,
    this.hideWatched = false,
    this.sort = CatalogSort.updated,
  })  : genres = genres ?? <String>{},
        countries = countries ?? <String>{};

  String types;
  String? allStatus;
  Set<String> genres;
  Set<String> countries;
  int? year;
  int? minimalAge;

  /// Client-side: drop titles rated below this (unrated titles are dropped too).
  double? minRating;

  /// Client-side: drop titles already present in the local watch history.
  bool hideWatched;

  CatalogSort sort;

  /// True when nothing beyond the content type is constrained.
  bool get isEmpty =>
      allStatus == null &&
      genres.isEmpty &&
      countries.isEmpty &&
      year == null &&
      minimalAge == null &&
      minRating == null &&
      !hideWatched;

  /// The slice of the filter reserved for the paid tier. Free users keep the
  /// category, status, year and sorting controls.
  bool get usesAdvancedFilters =>
      genres.isNotEmpty ||
      countries.isNotEmpty ||
      minimalAge != null ||
      minRating != null ||
      hideWatched;

  int get activeCount => (allStatus == null ? 0 : 1) +
      genres.length +
      countries.length +
      (year == null ? 0 : 1) +
      (minimalAge == null ? 0 : 1) +
      (minRating == null ? 0 : 1) +
      (hideWatched ? 1 : 0);

  Map<String, String> toQuery() => <String, String>{
        'types': types,
        if (allStatus != null) 'all_status': allStatus!,
        if (genres.isNotEmpty) 'genres': genres.join(','),
        if (countries.isNotEmpty) 'countries': countries.join(','),
        if (year != null) 'year': '$year',
        if (minimalAge != null) 'minimal_age': '$minimalAge',
        'sort': sort.value,
        'order': 'desc',
      };

  /// Applies the parts of the filter Kodik cannot express server-side.
  bool accepts(KodikTitle title, {Set<String> watched = const <String>{}}) {
    final threshold = minRating;
    if (threshold != null && (title.grade ?? 0) < threshold) return false;
    if (hideWatched && (watched.contains(title.id) || watched.contains(title.workId))) {
      return false;
    }
    return true;
  }

  CatalogFilter copy() => CatalogFilter(
        types: types,
        allStatus: allStatus,
        genres: <String>{...genres},
        countries: <String>{...countries},
        year: year,
        minimalAge: minimalAge,
        minRating: minRating,
        hideWatched: hideWatched,
        sort: sort,
      );

  /// Stable identity for widget keys — changes exactly when the query does.
  String get signature =>
      '$types|${allStatus ?? ''}|${(genres.toList()..sort()).join(",")}'
      '|${(countries.toList()..sort()).join(",")}|${year ?? ''}|${minimalAge ?? ''}'
      '|${minRating ?? ''}|$hideWatched|${sort.name}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'types': types,
        if (allStatus != null) 'all_status': allStatus,
        'genres': genres.toList(),
        'countries': countries.toList(),
        if (year != null) 'year': year,
        if (minimalAge != null) 'minimal_age': minimalAge,
        if (minRating != null) 'min_rating': minRating,
        'hide_watched': hideWatched,
        'sort': sort.name,
      };

  factory CatalogFilter.fromJson(Map<String, dynamic> j) => CatalogFilter(
        types: (j['types'] as String?) ?? KodikCatalog.dramas,
        allStatus: j['all_status'] as String?,
        genres: ((j['genres'] as List?) ?? const []).whereType<String>().toSet(),
        countries:
            ((j['countries'] as List?) ?? const []).whereType<String>().toSet(),
        year: (j['year'] as num?)?.toInt(),
        minimalAge: (j['minimal_age'] as num?)?.toInt(),
        minRating: (j['min_rating'] as num?)?.toDouble(),
        hideWatched: j['hide_watched'] == true,
        sort: CatalogSort.values.firstWhere(
          (s) => s.name == j['sort'],
          orElse: () => CatalogSort.updated,
        ),
      );
}
