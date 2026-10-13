import 'dart:async';
import 'dart:math' as math;

import 'playback_provider.dart';

/// Confirmed checkpoint plus conservative sampled watch time. Neither duration
/// nor completed is a promise that the provider reported an exact video length.
class PlaybackProgressSnapshot {
  final String sessionId;
  final String workId;
  final String providerId;
  final int season;
  final int episode;
  final int positionMs;
  final int? durationMs;
  final int watchedMs;
  final bool completed;

  const PlaybackProgressSnapshot({
    required this.sessionId, required this.workId, required this.providerId,
    required this.season, required this.episode, required this.positionMs,
    required this.durationMs, required this.watchedMs, required this.completed,
  });
}

/// One tracker per provider/episode generation. Unknown iframe events never
/// create a checkpoint. The UI captures its title in [save]; a new generation
/// gets a new tracker and closes this one before switching providers.
class PlaybackProgressTracker {
  final String sessionId;
  final String workId;
  final String providerId;
  final int season;
  final int episode;
  final Duration saveInterval;
  final DateTime Function() _now;
  final Future<void> Function(PlaybackProgressSnapshot)? save;

  PlaybackProgressTracker({
    required this.sessionId, required this.workId, required this.providerId,
    required this.season, required this.episode,
    this.saveInterval = const Duration(seconds: 5),
    DateTime Function()? now, this.save,
  }) : _now = now ?? DateTime.now {
    if (sessionId.isEmpty || workId.isEmpty || providerId.isEmpty ||
        season < 1 || episode < 1 || saveInterval.isNegative) {
      throw ArgumentError('A tracker must bind a valid playback generation');
    }
  }

  static const _maxMediaMs = 7 * 24 * 60 * 60 * 1000;
  bool _confirmed = false;
  bool _playing = false;
  bool _closed = false;
  bool _invalidEpisode = false;
  bool _completed = false;
  int _sequence = -1;
  int? _position;
  int? _duration;
  int _watchedMs = 0;
  DateTime? _lastSampleAt;
  int? _lastSamplePosition;
  DateTime? _lastSavedAt;
  DateTime? _lastQueuedAt;
  int _version = 0;
  int _savedVersion = -1;
  int _queuedVersion = -1;
  Timer? _timer;
  Future<void> _writes = Future<void>.value();
  Future<void>? _lastOperation;
  Object? lastSaveError;

  PlaybackProgressSnapshot? get snapshot {
    final position = _position;
    if (!_confirmed || position == null) return null;
    return PlaybackProgressSnapshot(
      sessionId: sessionId, workId: workId, providerId: providerId,
      season: season, episode: episode, positionMs: position,
      durationMs: _duration, watchedMs: _watchedMs, completed: _completed,
    );
  }

  /// Synchronous state transition before any await, so callbacks cannot reorder
  /// accepted sequence numbers while their saves are in flight.
  Future<void> accept(PlaybackEvent event) {
    if (_closed || _invalidEpisode || event.sessionId != sessionId ||
        event.sequence <= _sequence || event.sequence < 0) {
      return Future<void>.value();
    }
    _sequence = event.sequence;
    if ((event.season != null && event.season != season) ||
        (event.episode != null && event.episode != episode)) {
      _invalidEpisode = true;
      _playing = false;
      _lastSampleAt = null;
      return flush();
    }
    final at = _now();
    final oldPosition = _position;
    final oldDuration = _duration;
    final oldCompleted = _completed;
    final oldWatched = _watchedMs;
    final validDuration = event.durationMs != null && event.durationMs! > 0 &&
        event.durationMs! <= _maxMediaMs;
    if (validDuration) _duration = event.durationMs;
    final candidate = event.positionMs;
    final validPosition = candidate != null && candidate >= 0 &&
        candidate <= _maxMediaMs &&
        (_duration == null || candidate <= _duration! + 2000);
    if (validPosition) {
      _position = _duration == null ? candidate : math.min(candidate!, _duration!);
    }

    if (event.kind == PlaybackEventKind.play) {
      _confirmed = true;
      _playing = true;
      _completed = false;
      _lastSampleAt = at;
      _lastSamplePosition = _position;
    } else if (event.kind == PlaybackEventKind.seek) {
      // A seek changes resume position, but never becomes elapsed watch time.
      _completed = false;
      _lastSampleAt = at;
      _lastSamplePosition = _position;
    } else if (event.kind == PlaybackEventKind.time ||
        event.kind == PlaybackEventKind.pause ||
        event.kind == PlaybackEventKind.ended) {
      if (_playing && validPosition && _lastSampleAt != null &&
          _lastSamplePosition != null) {
        final elapsed = at.difference(_lastSampleAt!).inMilliseconds;
        final advanced = _position! - _lastSamplePosition!;
        // Long gaps, rewinds, and discontinuous jumps do not count. Playback
        // faster than normal may be undercounted rather than counting seeks.
        if (elapsed > 0 && elapsed <= 30000 && advanced > 0 &&
            advanced <= elapsed + 1500) {
          _watchedMs += math.min(advanced, elapsed);
        }
      }
      if (validPosition) {
        _lastSampleAt = at;
        _lastSamplePosition = _position;
      }
      if (event.kind == PlaybackEventKind.pause ||
          event.kind == PlaybackEventKind.ended) {
        _playing = false;
        _lastSampleAt = null;
        _lastSamplePosition = null;
      }
      if (event.kind == PlaybackEventKind.ended && _confirmed &&
          validPosition && _duration != null &&
          _position! >= _duration! - 1500) {
        _completed = true;
      }
    }
    if (oldPosition != _position || oldDuration != _duration ||
        oldCompleted != _completed || oldWatched != _watchedMs ||
        (_confirmed && _savedVersion < 0)) {
      _version++;
    }
    if (snapshot == null) return Future<void>.value();
    if (event.kind == PlaybackEventKind.pause ||
        event.kind == PlaybackEventKind.ended) return flush();
    return _schedule();
  }

  Future<void> _schedule() {
    if (save == null || _version <= _savedVersion || _version <= _queuedVersion) {
      return Future<void>.value();
    }
    final anchor = _lastQueuedAt ?? _lastSavedAt;
    final elapsed = anchor == null ? saveInterval : _now().difference(anchor);
    if (elapsed >= saveInterval) return flush();
    _timer ??= Timer(saveInterval - elapsed, () {
      _timer = null;
      unawaited(flush().catchError((Object error) { lastSaveError = error; }));
    });
    return Future<void>.value();
  }

  /// Explicit flush preserves the latest confirmed sample even after close.
  /// Caller errors are observable; a failed save does not poison the next one.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final value = snapshot;
    final callback = save;
    if (callback == null || value == null || _version <= _savedVersion) {
      return _writes;
    }
    if (_version <= _queuedVersion) return _lastOperation ?? _writes;
    final version = _version;
    _queuedVersion = version;
    _lastQueuedAt = _now();
    final operation = _writes.then((_) async {
      await callback(value);
      _savedVersion = version;
      _lastSavedAt = _now();
      lastSaveError = null;
    });
    _lastOperation = operation;
    _writes = operation.then<void>((_) {}, onError: (Object error, StackTrace _) {
      lastSaveError = error;
      if (_queuedVersion == version) {
        _queuedVersion = _savedVersion;
        _lastQueuedAt = null;
      }
    });
    return operation;
  }

  Future<void> close() {
    _closed = true;
    _playing = false;
    return flush();
  }
}
