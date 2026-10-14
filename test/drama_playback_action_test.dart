import 'package:flutter_test/flutter_test.dart';
import 'package:dramix/core/models.dart';
import 'package:dramix/core/storage.dart';
import 'package:dramix/ui/release/voiceover_screen.dart';

void main() {
  const refs = [
    KodikEpisodeRef(season: 1, episode: 1, url: 'https://example.test/1'),
    KodikEpisodeRef(season: 2, episode: 1, url: 'https://example.test/2'),
    KodikEpisodeRef(season: 2, episode: 2, url: 'https://example.test/3'),
  ];
  WatchEntry point(int season, int episode, int position) => WatchEntry(
    title: const SavedTitleRef(id: 'serial-1', title: 'Дорама'),
    season: season, episode: episode, positionMs: position,
    watchedAt: DateTime(2026));

  test('resume matches season and episode rather than duplicate episode number', () {
    expect(playbackStartIndex(refs, point(2, 2, 1000)), 2);
    expect(playbackActionLabel(refs, point(2, 2, 1000)),
      'Продолжить · Сезон 2 · Серия 2');
  });
  test('rendition missing saved episode starts in the selected season honestly', () {
    final saved = point(3, 1, 1000);
    expect(playbackStartIndex(refs, saved, selectedSeason: 2), 1);
    expect(playbackActionLabel(refs, saved, selectedSeason: 2),
      'Смотреть · Сезон 2 · Серия 1');
  });
  test('reset zero checkpoint does not advertise continue', () {
    expect(playbackStartIndex(refs, point(2, 2, 0)), 2);
    expect(playbackActionLabel(refs, point(2, 2, 0)),
      'Смотреть · Сезон 2 · Серия 2');
  });
  test('no checkpoint respects season selection, empty rendition has no CTA', () {
    expect(playbackStartIndex(refs, null, selectedSeason: 2), 1);
    expect(playbackStartIndex(const [], null), 0);
    expect(playbackActionLabel(const [], point(1, 1, 1000)),
      'Нет доступных серий');
  });
}
