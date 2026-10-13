import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dramix/core/playback_provider.dart';
import 'package:dramix/core/playback_progress.dart';

PlaybackEvent event(int sequence, PlaybackEventKind kind, {
  String sessionId = 'web-1', int? positionMs, int? durationMs,
  int? season, int? episode,
}) => PlaybackEvent(sessionId: sessionId, sequence: sequence, kind: kind,
    positionMs: positionMs, durationMs: durationMs, season: season, episode: episode);

void main() {
  late DateTime now;
  late List<PlaybackProgressSnapshot> saved;
  late PlaybackProgressTracker tracker;
  setUp(() {
    now = DateTime(2024);
    saved = [];
    tracker = PlaybackProgressTracker(
      sessionId: 'web-1', workId: 'kinopoisk:7', providerId: 'serial-1',
      season: 1, episode: 2, now: () => now,
      save: (value) async { saved.add(value); },
    );
  });
  tearDown(() async { await tracker.close(); });

  test('metadata time and seeks alone never create history', () async {
    await tracker.accept(event(1, PlaybackEventKind.duration,
        positionMs: 0, durationMs: 60000));
    await tracker.accept(event(2, PlaybackEventKind.time, positionMs: 1000));
    await tracker.accept(event(3, PlaybackEventKind.seek, positionMs: 30000));
    await tracker.close();
    expect(saved, isEmpty);
    expect(tracker.snapshot, isNull);
  });

  test('confirmed play binds exact work dub episode and permits zero', () async {
    await tracker.accept(event(1, PlaybackEventKind.play, positionMs: 0));
    expect(saved, hasLength(1));
    expect(saved.single.workId, 'kinopoisk:7');
    expect(saved.single.providerId, 'serial-1');
    expect(saved.single.season, 1);
    expect(saved.single.episode, 2);
    expect(saved.single.positionMs, 0);
  });

  test('play without a known position cannot overwrite a checkpoint', () async {
    await tracker.accept(event(1, PlaybackEventKind.play));
    await tracker.accept(event(2, PlaybackEventKind.pause));
    expect(saved, isEmpty);
    await tracker.accept(event(3, PlaybackEventKind.play, positionMs: 5000));
    await tracker.accept(event(4, PlaybackEventKind.time, positionMs: -1));
    await tracker.flush();
    expect(saved.last.positionMs, 5000);
  });

  test('stale sessions sequences and mismatching episodes are rejected', () async {
    await tracker.accept(event(1, PlaybackEventKind.play, positionMs: 1000));
    await tracker.accept(event(2, PlaybackEventKind.time,
        sessionId: 'old-web', positionMs: 9000));
    await tracker.accept(event(1, PlaybackEventKind.time, positionMs: 9000));
    expect(tracker.snapshot!.positionMs, 1000);
    await tracker.accept(event(3, PlaybackEventKind.episodeChanged,
        season: 1, episode: 3, positionMs: 0));
    await tracker.accept(event(4, PlaybackEventKind.play, positionMs: 0));
    expect(tracker.snapshot!.episode, 2);
    expect(tracker.snapshot!.positionMs, 1000);
  });

  test('throttles time updates and pause forces the latest snapshot', () async {
    await tracker.accept(event(1, PlaybackEventKind.play, positionMs: 0));
    now = now.add(const Duration(seconds: 1));
    await tracker.accept(event(2, PlaybackEventKind.time, positionMs: 1000));
    now = now.add(const Duration(seconds: 1));
    await tracker.accept(event(3, PlaybackEventKind.time, positionMs: 2000));
    expect(saved, hasLength(1));
    await tracker.accept(event(4, PlaybackEventKind.pause, positionMs: 2000));
    expect(saved, hasLength(2));
    expect(saved.last.positionMs, 2000);
    expect(saved.last.watchedMs, 2000);
  });

  test('seek and long unknown gaps are not counted as watch time', () async {
    await tracker.accept(event(1, PlaybackEventKind.play,
        positionMs: 0, durationMs: 120000));
    now = now.add(const Duration(seconds: 1));
    await tracker.accept(event(2, PlaybackEventKind.time, positionMs: 1000));
    await tracker.accept(event(3, PlaybackEventKind.seek, positionMs: 90000));
    now = now.add(const Duration(seconds: 1));
    await tracker.accept(event(4, PlaybackEventKind.time, positionMs: 91000));
    expect(tracker.snapshot!.watchedMs, 2000);
    now = now.add(const Duration(seconds: 45));
    await tracker.accept(event(5, PlaybackEventKind.time, positionMs: 120000));
    expect(tracker.snapshot!.watchedMs, 2000);
    await tracker.accept(event(6, PlaybackEventKind.seek, positionMs: 0));
    await tracker.flush();
    expect(saved.last.positionMs, 0);
    expect(saved.last.watchedMs, 2000);
  });

  test('ended completion requires confirmed play and a valid near-end sample', () async {
    await tracker.accept(event(1, PlaybackEventKind.ended,
        positionMs: 60000, durationMs: 60000));
    expect(tracker.snapshot, isNull);
    await tracker.accept(event(2, PlaybackEventKind.play,
        positionMs: 1000, durationMs: 60000));
    await tracker.accept(event(3, PlaybackEventKind.ended, positionMs: 60000));
    expect(saved.last.completed, isTrue);
    await tracker.accept(event(4, PlaybackEventKind.seek, positionMs: 0));
    expect(tracker.snapshot!.completed, isFalse);
  });

  test('late duration metadata cannot reset confirmed playback position', () async {
    await tracker.accept(event(1, PlaybackEventKind.play, positionMs: 30000));
    await tracker.accept(event(2, PlaybackEventKind.duration,
        positionMs: 0, durationMs: 60000));
    await tracker.flush();
    expect(saved.last.positionMs, 30000);
    expect(saved.last.durationMs, 60000);
  });

  test('unbounded positions and invalid duration cannot replace known values', () async {
    await tracker.accept(event(1, PlaybackEventKind.play,
        positionMs: 1000, durationMs: 60000));
    await tracker.accept(event(2, PlaybackEventKind.time,
        positionMs: 1 << 60, durationMs: -1));
    await tracker.flush();
    expect(tracker.snapshot!.positionMs, 1000);
    expect(tracker.snapshot!.durationMs, 60000);
  });

  test('queued writes capture snapshots and cannot cross provider generation', () async {
    final pending = Completer<void>();
    tracker = PlaybackProgressTracker(
      sessionId: 'web-1', workId: 'kinopoisk:7', providerId: 'serial-1',
      season: 1, episode: 2, now: () => now,
      save: (value) async {
        saved.add(value);
        if (saved.length == 1) await pending.future;
      },
    );
    final first = tracker.accept(event(1, PlaybackEventKind.play, positionMs: 1000));
    await Future<void>.delayed(Duration.zero);
    await tracker.accept(event(2, PlaybackEventKind.time, positionMs: 2000));
    expect(saved, hasLength(1));
    final closing = tracker.close();
    await tracker.accept(event(3, PlaybackEventKind.time, positionMs: 9000));
    pending.complete();
    await Future.wait([first, closing]);
    expect(saved, hasLength(2));
    expect(saved.last.positionMs, 2000);
    expect(saved.every((s) => s.sessionId == 'web-1' && s.episode == 2), isTrue);
  });

  test('failed save can retry and close shares pending failure', () async {
    var attempts = 0;
    tracker = PlaybackProgressTracker(
      sessionId: 'web-1', workId: 'kinopoisk:7', providerId: 'serial-1',
      season: 1, episode: 2,
      save: (value) async {
        attempts++;
        if (attempts == 1) throw StateError('disk unavailable');
        saved.add(value);
      },
    );
    await expectLater(tracker.accept(event(1, PlaybackEventKind.play,
        positionMs: 1000)), throwsStateError);
    await tracker.flush();
    expect(attempts, 2);
    expect(saved.single.positionMs, 1000);
  });
}
