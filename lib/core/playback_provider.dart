import 'dart:convert';

/// Common events emitted by an explicitly supported playback adapter.
/// Time and seek do not prove playback started or that elapsed time was watched.
enum PlaybackEventKind { play, pause, time, duration, seek, ended, episodeChanged, error }

class PlaybackEvent {
  final String sessionId;
  final int sequence;
  final PlaybackEventKind kind;
  final int? positionMs;
  final int? durationMs;
  final int? season;
  final int? episode;
  final int? translationId;

  const PlaybackEvent({
    required this.sessionId,
    required this.sequence,
    required this.kind,
    this.positionMs,
    this.durationMs,
    this.season,
    this.episode,
    this.translationId,
  });
}

/// Protocol support, not a claim that a particular iframe emitted an event.
/// Position tracking still requires a verified source bridge on each platform.
class PlaybackCapabilities {
  final bool reportsPosition;
  final bool reportsDuration;
  final bool reportsPlayPause;
  final bool reportsEnded;
  final bool tracksEmbeddedEpisode;
  final bool resumeSeek;

  const PlaybackCapabilities({
    this.reportsPosition = false,
    this.reportsDuration = false,
    this.reportsPlayPause = false,
    this.reportsEnded = false,
    this.tracksEmbeddedEpisode = false,
    this.resumeSeek = false,
  });
}

abstract class PlaybackProvider {
  String get id;
  PlaybackCapabilities get capabilities;
  bool supportsFrameUri(Uri uri);

  PlaybackSession? openSession({
    required Uri frameUri,
    required String sessionId,
    required int epoch,
    required String episodeKey,
    required int season,
    required int episode,
    bool isMovie = false,
    int? translationId,
  });
}

abstract class PlaybackSession {
  PlaybackEvent? parseMessage(
    Object? data, {
    required String origin,
    required bool sourceVerified,
    required int epoch,
    required String episodeKey,
    required int sequence,
  });
}

/// Kodik's postMessage protocol; no media extraction or unverified commands.
class KodikPlaybackProvider implements PlaybackProvider {
  const KodikPlaybackProvider();

  // Explicit aliases for one provider. Origin is pinned to the selected iframe.
  static const allowedHosts = {'kodikplayer.com', 'kodik.info', 'aniqit.com'};

  @override
  String get id => 'kodik';

  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
        reportsPosition: true,
        reportsDuration: true,
        reportsPlayPause: true,
        reportsEnded: true,
        tracksEmbeddedEpisode: true,
        resumeSeek: false,
      );

  @override
  bool supportsFrameUri(Uri uri) =>
      uri.scheme == 'https' &&
      allowedHosts.contains(uri.host) &&
      uri.port == 443 &&
      uri.userInfo.isEmpty;

  @override
  KodikPlaybackSession? openSession({
    required Uri frameUri,
    required String sessionId,
    required int epoch,
    required String episodeKey,
    required int season,
    required int episode,
    bool isMovie = false,
    int? translationId,
  }) {
    if (!supportsFrameUri(frameUri) ||
        sessionId.isEmpty ||
        episodeKey.isEmpty ||
        epoch < 0 ||
        season < 1 ||
        episode < 1) {
      return null;
    }
    return KodikPlaybackSession._(
      expectedOrigin: Uri(scheme: 'https', host: frameUri.host).origin,
      sessionId: sessionId,
      epoch: epoch,
      episodeKey: episodeKey,
      season: season,
      episode: episode,
      isMovie: isMovie,
      translationId: translationId,
    );
  }
}

/// One embed lifetime, bound to the selected episode and frame origin.
///
/// Web must verify MessageEvent.source equals iframe.contentWindow. Native
/// wrappers verify the iframe sender in their main-frame listener and use a
/// private nonce for the Dart bridge envelope. Never obtain sourceVerified,
/// epoch, episodeKey or sequence from provider-controlled payloads.
class KodikPlaybackSession implements PlaybackSession {
  KodikPlaybackSession._({
    required this.expectedOrigin,
    required this.sessionId,
    required this.epoch,
    required this.episodeKey,
    required this.season,
    required this.episode,
    required this.isMovie,
    required this.translationId,
  });

  final String expectedOrigin;
  final String sessionId;
  final int epoch;
  final String episodeKey;
  final int season;
  final int episode;
  final bool isMovie;
  final int? translationId;

  bool get isSuspended => !_episodeMatches;

  int _lastSequence = -1;
  bool _episodeMatches = true;

  static int? _milliseconds(Object? seconds) {
    if (seconds is! num ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds > 7 * 24 * 60 * 60) {
      return null;
    }
    return (seconds * 1000).round();
  }

  static int? _episodeNumber(Object? number) {
    if (number is! int || number < 1 || number > 100000) return null;
    return number;
  }

  bool _originMatches(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.path.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        Uri(scheme: 'https', host: uri.host).origin == expectedOrigin;
  }

  @override
  PlaybackEvent? parseMessage(
    Object? data, {
    required String origin,
    required bool sourceVerified,
    required int epoch,
    required String episodeKey,
    required int sequence,
  }) {
    if (!sourceVerified ||
        !_originMatches(origin) ||
        epoch != this.epoch ||
        episodeKey != this.episodeKey ||
        sequence < 0 ||
        sequence <= _lastSequence) {
      return null;
    }
    Object? decoded = data;
    if (decoded is String) {
      if (decoded.length > 8192) return null;
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return null;
      }
    }
    if (decoded is! Map || decoded['key'] is! String) return null;
    final key = decoded['key'];
    final value = decoded['value'];
    PlaybackEventKind kind;
    int? positionMs;
    int? durationMs;
    int? observedSeason;
    int? observedEpisode;
    int? observedTranslation;

    switch (key) {
      case 'kodik_player_current_episode':
        _episodeMatches = false;
        if (value is! Map ||
            !value.containsKey('season') ||
            !value.containsKey('episode')) {
          return null;
        }
        // Movies may report both coordinates as null; retain the bound 1/1.
        if (value['season'] == null && value['episode'] == null) {
          if (!isMovie || season != 1 || episode != 1) return null;
          observedSeason = 1;
          observedEpisode = 1;
        } else {
          observedSeason = _episodeNumber(value['season']);
          observedEpisode = _episodeNumber(value['episode']);
          if (observedSeason == null || observedEpisode == null) return null;
        }
        final translation = value['translation'];
        if (translation is Map && translation['id'] is int) {
          final id = translation['id'] as int;
          if (id > 0 && id <= 1000000000) observedTranslation = id;
        }
        _episodeMatches = observedSeason == season &&
            observedEpisode == episode &&
            (translationId == null || observedTranslation == translationId);
        kind = PlaybackEventKind.episodeChanged;
      case 'kodik_player_play':
      case 'kodik_player_video_started':
        kind = PlaybackEventKind.play;
      case 'kodik_player_pause':
        kind = PlaybackEventKind.pause;
      case 'kodik_player_time_update':
        positionMs = _milliseconds(value);
        if (positionMs == null) return null;
        kind = PlaybackEventKind.time;
      case 'kodik_player_duration_update':
        durationMs = _milliseconds(value);
        if (durationMs == null || durationMs == 0) return null;
        kind = PlaybackEventKind.duration;
      case 'kodik_player_seek':
        if (value is! Map) return null;
        positionMs = _milliseconds(value['time']);
        if (positionMs == null) return null;
        kind = PlaybackEventKind.seek;
      case 'kodik_player_video_ended':
        kind = PlaybackEventKind.ended;
      default:
        return null;
    }
    if (!_episodeMatches && kind != PlaybackEventKind.episodeChanged) return null;
    _lastSequence = sequence;
    return PlaybackEvent(
      sessionId: sessionId,
      sequence: sequence,
      kind: kind,
      positionMs: positionMs,
      durationMs: durationMs,
      season: observedSeason,
      episode: observedEpisode,
      translationId: observedTranslation,
    );
  }
}
