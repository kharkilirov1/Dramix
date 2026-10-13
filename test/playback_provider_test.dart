import 'package:flutter_test/flutter_test.dart';
import 'package:dramix/core/playback_provider.dart';

void main() {
  const provider = KodikPlaybackProvider();
  KodikPlaybackSession session({int episode = 2, bool isMovie = false, int? translationId}) =>
      provider.openSession(
        frameUri: Uri.parse('https://kodikplayer.com/serial/synthetic/720p'),
        sessionId: 'session-a',
        epoch: 7,
        episodeKey: 'work-a:1:$episode',
        season: 1,
        episode: episode,
        isMovie: isMovie,
        translationId: translationId,
      )!;

  PlaybackEvent? parse(KodikPlaybackSession session, Object? payload,
      {int sequence = 0, String origin = 'https://kodikplayer.com',
      bool sourceVerified = true, int epoch = 7, String? episodeKey}) =>
      session.parseMessage(
        payload,
        origin: origin,
        sourceVerified: sourceVerified,
        epoch: epoch,
        episodeKey: episodeKey ?? session.episodeKey,
        sequence: sequence,
      );

  test('only explicit HTTPS Kodik hosts advertise usable sessions', () {
    for (final url in [
      'https://unknown.example/serial/1',
      'https://kodikplayer.com.evil.test/video/1',
      'https://sub.kodikplayer.com/video/1',
      'http://kodikplayer.com/video/1',
      'https://kodikplayer.com:8443/video/1',
      'https://user@kodikplayer.com/video/1',
    ]) {
      expect(provider.supportsFrameUri(Uri.parse(url)), isFalse);
      expect(provider.openSession(
        frameUri: Uri.parse(url), sessionId: 'a', epoch: 1,
        episodeKey: 'w:1:1', season: 1, episode: 1), isNull);
    }
    expect(provider.capabilities.resumeSeek, isFalse);
    expect(provider.capabilities.directMediaResolution, isFalse);
    expect(provider.capabilities.reportsPosition, isTrue);
  });

  test('source origin local epoch and episode binding are mandatory', () {
    final bound = session();
    const data = {'key': 'kodik_player_play'};
    expect(parse(bound, data, sourceVerified: false), isNull);
    expect(parse(bound, data, origin: 'null'), isNull);
    expect(parse(bound, data, origin: 'https://kodik.info'), isNull);
    expect(parse(bound, data, origin: 'https://kodikplayer.com/path'), isNull);
    expect(parse(bound, data, origin: 'https://kodikplayer.com?x=1'), isNull);
    expect(parse(bound, data, epoch: 8), isNull);
    expect(parse(bound, data, episodeKey: 'work-b:1:2'), isNull);
    expect(parse(bound, data)!.kind, PlaybackEventKind.play);
  });

  test('JSON strings and numeric seconds decode into typed milliseconds', () {
    final bound = session();
    final position = parse(bound, '{"key":"kodik_player_time_update","value":1.25}')!;
    expect(position.kind, PlaybackEventKind.time);
    expect(position.positionMs, 1250);
    expect(position.sessionId, 'session-a');
    final duration = parse(bound,
      {'key': 'kodik_player_duration_update', 'value': 300.5}, sequence: 1)!;
    expect(duration.durationMs, 300500);
  });

  test('duplicate and out-of-order sequence cannot mutate active playback', () {
    final bound = session();
    const data = {'key': 'kodik_player_play'};
    expect(parse(bound, data, sequence: 2), isNotNull);
    expect(parse(bound, data, sequence: 2), isNull);
    expect(parse(bound, data, sequence: 1), isNull);
    expect(parse(bound, {'key': 'kodik_player_pause'}, sequence: 3)!.kind,
      PlaybackEventKind.pause);
  });

  test('non-finite negative coerced and unreasonable positions are rejected', () {
    for (final value in [double.nan, double.infinity, -1, '20', true, null, 604801]) {
      final bound = session();
      expect(parse(bound, {'key': 'kodik_player_time_update', 'value': value}), isNull);
      expect(parse(bound, {'key': 'kodik_player_duration_update', 'value': value}), isNull);
    }
    expect(parse(session(), {'key': 'kodik_player_duration_update', 'value': 0}), isNull);
  });

  test('seek is distinct from playback and never invents duration', () {
    final event = parse(session(), {'key': 'kodik_player_seek', 'value': {'time': 99.5}})!;
    expect(event.kind, PlaybackEventKind.seek);
    expect(event.positionMs, 99500);
    expect(event.durationMs, isNull);
    expect(parse(session(), {'key': 'kodik_player_seek', 'value': 99}), isNull);
  });

  test('embedded episode mismatch blocks subsequent progress until rebound', () {
    final bound = session();
    final changed = parse(bound, {
      'key': 'kodik_player_current_episode',
      'value': {'season': 1, 'episode': 3}
    })!;
    expect(changed.kind, PlaybackEventKind.episodeChanged);
    expect(changed.episode, 3);
    expect(parse(bound, {'key': 'kodik_player_play'}, sequence: 1), isNull);
    expect(parse(bound, {'key': 'kodik_player_time_update', 'value': 50}, sequence: 2), isNull);
    expect(parse(bound, {
      'key': 'kodik_player_current_episode',
      'value': {'season': 1, 'episode': 2}
    }, sequence: 3), isNotNull);
    expect(parse(bound, {'key': 'kodik_player_play'}, sequence: 4), isNotNull);
  });

  test('unknown malformed commands and FrameXTV shapes never become events', () {
    for (final data in [
      {'event': 'play', 'currentTime': 1},
      {'type': 'timeupdate', 'time': 1},
      {'key': 'kodik_player_api', 'value': {'method': 'play'}},
      {'key': 'kodik_player_unknown', 'value': 1},
      '[1,2]',
      'not json',
      ' ' * 8193,
      null,
    ]) {
      expect(parse(session(), data), isNull);
    }
  });

  test('null movie coordinates require explicit movie context', () {
    const data = {
      'key': 'kodik_player_current_episode',
      'value': {'season': null, 'episode': null}
    };
    expect(parse(session(episode: 1), data), isNull);
    expect(parse(session(episode: 1, isMovie: true), data)!.episode, 1);
    expect(parse(session(episode: 1, isMovie: true),
      {'key': 'kodik_player_current_episode', 'value': {}}), isNull);
  });

  test('play video-start and ended use actual Kodik event keys', () {
    expect(parse(session(), {'key': 'kodik_player_video_started'})!.kind,
      PlaybackEventKind.play);
    expect(parse(session(), {'key': 'kodik_player_video_ended'})!.kind,
      PlaybackEventKind.ended);
  });

  test('embedded translation change suspends stream takeover and progress', () {
    final bound = session(translationId: 9);
    final changed = parse(bound, {
      'key': 'kodik_player_current_episode',
      'value': {'season': 1, 'episode': 2, 'translation': {'id': 10}}
    })!;
    expect(changed.translationId, 10);
    expect(bound.isSuspended, isTrue);
    expect(parse(bound, {'key': 'kodik_player_play'}, sequence: 1), isNull);
    parse(bound, {
      'key': 'kodik_player_current_episode',
      'value': {'season': 1, 'episode': 2, 'translation': {'id': 9}}
    }, sequence: 2);
    expect(bound.isSuspended, isFalse);
  });

}
