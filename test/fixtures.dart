import 'dart:convert';

import 'package:http/http.dart' as http;

/// Chaos-encoded UTF-8 response, matching how `kodik-api.com` replies.
http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// A real `foreign-serial` record (Korean drama) trimmed to the fields the app
/// consumes. Captured from a live `/search?title=Винченцо` response.
final Map<String, dynamic> vincenzoJson = <String, dynamic>{
  'id': 'serial-32799',
  'type': 'foreign-serial',
  'link': '//kodikplayer.com/serial/32799/cf37d28128e776ba1f40415efabc05bd/720p',
  'title': 'Винченцо',
  'title_orig': 'Vincenzo',
  'year': 2021,
  'episodes_count': 20,
  'last_season': 1,
  'last_episode': 20,
  'quality': 'WEB-DLRip 720p',
  'camrip': false,
  'lgbt': false,
  'kinopoisk_id': '1398913',
  'imdb_id': 'tt11527492',
  'translation': {'id': 639, 'title': 'SoftBox', 'type': 'voice'},
  'screenshots': ['https://i.kodik.biz/screenshots/seria/790235/1.jpg'],
  'seasons': {
    '1': {
      'link': '//kodikplayer.com/season/68285/88a00cf646a66484dd1b1f6b6719ff3a/720p',
      'episodes': {
        '1': '//kodikplayer.com/seria/790235/88a00cf646a66484dd1b1f6b6719ff3a/720p',
        '2': '//kodikplayer.com/seria/792575/cb36f07ef81449effddd2a4e56df3f3d/720p',
      },
    },
  },
  'material_data': {
    'poster_url': 'https://st.kp.yandex.net/images/film_big/1398913.jpg',
    'description':
        'В восьмилетнем возрасте Пак Чу-хён был усыновлён итальянской семьёй.',
    'all_genres': ['драма', 'комедия', 'криминал'],
    'countries': ['Корея Южная'],
    'duration': 80,
    'kinopoisk_rating': 8.4,
    'imdb_rating': 8.4,
    'kinopoisk_votes': 42117,
    'actors': ['Сон Джун-ги', 'Чон Ё-бин', 'Тхэгён'],
    'rating_mpaa': 'pg-13',
  },
};

/// A single-film entry with no season tree — exercises the `link` fallback.
final Map<String, dynamic> movieJson = <String, dynamic>{
  'id': 'movie-108152',
  'type': 'foreign-movie',
  'link': '//kodikplayer.com/video/108152/869f513fbac154c33b73dcce24187bd2/720p',
  'title': 'Невеста',
  'title_orig': 'The Bride',
  'year': 2024,
  'camrip': true,
  'quality': 'TS 720p',
  'translation': {'id': 1062, 'title': 'LE-Production', 'type': 'voice'},
  'material_data': {
    'poster_url': 'https://st.kp.yandex.net/images/film_big/6634211.jpg',
    'all_genres': ['ужасы'],
    'countries': ['США'],
    'kinopoisk_rating': 6.1,
  },
};
