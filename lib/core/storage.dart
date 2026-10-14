import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// A user-maintained list, mirroring the reference client's list statuses.
enum WatchStatus {
  watching(1, 'Смотрю'),
  plans(2, 'В планах'),
  completed(3, 'Просмотрено'),
  holdOn(4, 'Отложено'),
  dropped(5, 'Брошено');

  const WatchStatus(this.value, this.title);

  final int value;
  final String title;

  static WatchStatus? fromValue(int? value) {
    for (final s in WatchStatus.values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// A playback checkpoint shown in the "История" list.
class WatchEntry {
  final SavedTitleRef title;
  final int? season;
  final int? episode;
  final int positionMs;
  final DateTime watchedAt;

  const WatchEntry({
    required this.title,
    this.season,
    this.episode,
    this.positionMs = 0,
    required this.watchedAt,
  });

  String get label {
    final parts = <String>[];
    if (season != null && season! > 1) parts.add('сезон $season');
    if (episode != null) parts.add('серия $episode');
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title.toJson(),
        if (season != null) 'season': season,
        if (episode != null) 'episode': episode,
        'positionMs': positionMs,
        'watchedAt': watchedAt.toIso8601String(),
      };

  factory WatchEntry.fromJson(Map<String, dynamic> j) => WatchEntry(
        title: SavedTitleRef.fromJson(
            (j['title'] as Map?)?.cast<String, dynamic>() ?? const {}),
        season: (j['season'] as num?)?.toInt(),
        episode: (j['episode'] as num?)?.toInt(),
        positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
        watchedAt: DateTime.tryParse((j['watchedAt'] as String?) ?? '') ??
            DateTime.now(),
      );
}

/// Aggregated local profile numbers for the Профиль screen.
class LibraryStats {
  final int watchedEpisodes;
  final int watchedSeconds;
  final int historySize;
  final int favorites;
  final Map<int, int> listCounts;

  const LibraryStats({
    this.watchedEpisodes = 0,
    this.watchedSeconds = 0,
    this.historySize = 0,
    this.favorites = 0,
    this.listCounts = const <int, int>{},
  });

  int countFor(WatchStatus status) => listCounts[status.value] ?? 0;

  /// Days of watch time, matching how the reference client reports it.
  int get watchedDays => watchedSeconds ~/ Duration.secondsPerDay;
}

/// Local, offline-first state: history, favourites, watch lists and profile
/// numbers. Kodik has no user accounts, so all of this lives on the device.
class Library {
  const Library._();

  /// Bumped whenever stored data changes, so already-mounted screens can
  /// refresh instead of going stale behind the tab switcher.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const String _historyKey = 'dramix.history';
  static const String _favoritesKey = 'dramix.favorites';
  static const String _listsKey = 'dramix.lists';
  static const String _ratingsKey = 'dramix.ratings';
  static const String _searchKey = 'dramix.search';
  static const String _myTabKey = 'dramix.myTab';
  static const int maxSearch = 15;

  /// Legacy presentation limits. Durable checkpoints are never trimmed.
  static const int maxHistory = 200;
  static const int freeHistory = 30;

  // Serialize read-modify-write operations on the history key. Keep failures
  // on the caller's future without poisoning subsequent writes.
  static Future<void> _historyWrites = Future<void>.value();

  static Future<T> _mutateHistory<T>(Future<T> Function() action) {
    final operation = _historyWrites.then((_) => action());
    _historyWrites = operation.then<void>((_) {},
        onError: (Object _, StackTrace __) {});
    return operation;
  }


  static const String _aliasesKey = 'dramix.workAliases.v1';
  static const String _backupKey = 'dramix.libraryBackup.v1';

  static Map<String, String> _aliases(SharedPreferences prefs) {
    final raw = prefs.getString(_aliasesKey);
    if (raw == null) return <String, String>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.entries.any((e) =>
        e.key is! String || e.value is! String || (e.value as String).isEmpty)) {
      throw const FormatException('Invalid work aliases');
    }
    return <String, String>{
      for (final e in decoded.entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
  }

  /// Original guest data is copied once before learning aliases. No legacy key
  /// is rewritten by registration; unknown records remain separate.
  static Future<void> _registerTitle(SavedTitleRef title) async {
    if (title.id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final previous = aliases[title.id];
    final next = title.workId;
    if (previous == next) return;
    // Do not silently remap an established external identity on metadata drift.
    if (previous != null && !previous.startsWith('kodik:')) return;
    if (!prefs.containsKey(_backupKey)) {
      final backup = <String, dynamic>{
        'version': 1,
        for (final key in [_historyKey, _favoritesKey, _listsKey, _ratingsKey])
          if (prefs.containsKey(key)) key: prefs.get(key),
      };
      if (!await prefs.setString(_backupKey, jsonEncode(backup))) {
        throw StateError('Unable to back up guest library');
      }
    }
    aliases[title.id] = next;
    if (!await prefs.setString(_aliasesKey, jsonEncode(aliases))) {
      throw StateError('Unable to persist work identity');
    }
  }

  static Future<void> registerTitle(SavedTitleRef title) =>
      _mutateHistory(() => _registerTitle(title));

  /// Resolves either a provider record id or an already canonical work key.
  static String _resolveKey(String id, Map<String, String> aliases) =>
      aliases[id] ??
      (id.startsWith('kodik:') ? aliases[id.substring(6)] : null) ?? id;

  static Future<String> workId(String id) async {
    await _historyWrites;
    final prefs = await SharedPreferences.getInstance();
    return _resolveKey(id, _aliases(prefs));
  }

  static String _identity(SavedTitleRef ref, Map<String, String> aliases) =>
      aliases[ref.id] ?? ref.workId;

  static Future<List<WatchEntry>> continueWatching({int limit = 12}) async {
    if (limit <= 0) return <WatchEntry>[];
    final entries = await history();
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final seen = <String>{};
    final out = <WatchEntry>[];
    for (final entry in entries) {
      final key = _identity(entry.title, aliases);
      if (!seen.add(key)) continue;
      // The latest checkpoint wins, including an intentional reset to zero.
      if (entry.positionMs <= 0) continue;
      out.add(entry);
      if (out.length >= limit) break;
    }
    return out;
  }

  // --------------------------------------------------------------- history

  static Future<List<WatchEntry>> history() async {
    await _historyWrites;
    return _history();
  }

  static Future<List<WatchEntry>> _history() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getStringList(_historyKey))
        .map(WatchEntry.fromJson)
        .toList();
  }

  /// Records a playback checkpoint, moving the title to the top and collapsing
  /// earlier entries for the same episode.
  static Future<void> record(WatchEntry entry) => _mutateHistory(() async {
    await _registerTitle(entry.title);
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final list = _decodeList(prefs.getStringList(_historyKey))
        .map(WatchEntry.fromJson)
        .where((e) => !(_identity(e.title, aliases) == _identity(entry.title, aliases) &&
            e.season == entry.season &&
            e.episode == entry.episode))
        .toList();
    list.insert(0, entry);
    await prefs.setStringList(
        _historyKey, list.map((e) => jsonEncode(e.toJson())).toList());
    revision.value++;
  });

  static Future<void> clearHistory() => _mutateHistory(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    revision.value++;
  });

  /// Most recent checkpoint for a title, used for "continue watching".
  static Future<WatchEntry?> resumePoint(String titleId) async {
    final entries = await history();
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final target = _resolveKey(titleId, aliases);
    for (final e in entries) {
      if (e.title.id == titleId || _identity(e.title, aliases) == target) return e;
    }
    return null;
  }


  /// Exact episode checkpoint across known dubbing aliases.
  static Future<WatchEntry?> episodeCheckpoint(
      String titleId, int? season, int? episode) async {
    final entries = await history();
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final target = _resolveKey(titleId, aliases);
    for (final entry in entries) {
      if ((entry.title.id == titleId || _identity(entry.title, aliases) == target) &&
          entry.season == season && entry.episode == episode) return entry;
    }
    return null;
  }

  /// Ids of every title present in the local history — powers «скрыть
  /// просмотренное» in the catalog.
  static Future<Set<String>> watchedTitleIds() async {
    final entries = await history();
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final works = <String>{for (final e in entries) _identity(e.title, aliases)};
    return <String>{
      ...works,
      for (final e in entries) e.title.id,
      for (final alias in aliases.entries)
        if (works.contains(alias.value)) alias.key,
    };
  }

  // ------------------------------------------------------------- favourites

  static Future<List<SavedTitleRef>> favorites() async {
    await _historyWrites;
    return _favorites();
  }

  static Future<List<SavedTitleRef>> _favorites() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getStringList(_favoritesKey))
        .map(SavedTitleRef.fromJson)
        .toList();
  }

  static Future<bool> isFavorite(String id) async {
    final entries = await favorites();
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final target = _resolveKey(id, aliases);
    for (final e in entries) {
      if (e.id == id || _identity(e, aliases) == target) return true;
    }
    return false;
  }

  /// Adds or removes a title; returns the new state (`true` = favourited).
  static Future<bool> toggleFavorite(SavedTitleRef title) => _mutateHistory(() async {
    await _registerTitle(title);
    final prefs = await SharedPreferences.getInstance();
    final list = await _favorites();
    final aliases = _aliases(prefs);
    final target = _identity(title, aliases);
    final exists = list.any((e) => _identity(e, aliases) == target);
    final next = exists
        ? list.where((e) => _identity(e, aliases) != target).toList()
        : <SavedTitleRef>[title, ...list];
    await prefs.setStringList(
        _favoritesKey, next.map((e) => jsonEncode(e.toJson())).toList());
    revision.value++;
    return !exists;
  });

  static Future<void> clearFavorites() => _mutateHistory(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_favoritesKey);
    revision.value++;
  });

  // ------------------------------------------------------------ watch lists

  static Future<Map<String, ({int status, SavedTitleRef title})>>
      _listEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_listsKey);
    final out = <String, ({int status, SavedTitleRef title})>{};
    if (raw == null || raw.isEmpty) return out;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (value is! Map) return;
          final m = value.cast<String, dynamic>();
          final status = (m['status'] as num?)?.toInt();
          final title = m['title'];
          if (status == null || title is! Map) return;
          out['$key'] = (
            status: status,
            title: SavedTitleRef.fromJson(title.cast<String, dynamic>()),
          );
        });
      }
    } catch (_) {
      // Treat a corrupt store as empty rather than breaking the screen.
    }
    return out;
  }

  static Future<void> _writeLists(
      Map<String, ({int status, SavedTitleRef title})> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{
      for (final e in entries.entries)
        e.key: <String, dynamic>{
          'status': e.value.status,
          'title': e.value.title.toJson(),
        },
    };
    await prefs.setString(_listsKey, jsonEncode(encoded));
    revision.value++;
  }

  static Future<int?> watchStatus(String id) async {
    await _historyWrites;
    final entries = await _listEntries();
    if (entries.containsKey(id)) return entries[id]!.status;
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final target = _resolveKey(id, aliases);
    for (final entry in entries.values) {
      if (_identity(entry.title, aliases) == target) return entry.status;
    }
    return null;
  }

  /// Assigns (or clears) a watch list for a title.
  static Future<void> setWatchStatus(
      SavedTitleRef title, WatchStatus? status) => _mutateHistory(() async {
    await _registerTitle(title);
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    final entries = await _listEntries();
    entries.removeWhere((_, value) =>
        _identity(value.title, aliases) == _identity(title, aliases));
    if (status == null) {
      entries.remove(title.id);
    } else {
      entries[title.id] = (status: status.value, title: title);
    }
    await _writeLists(entries);
  });

  static Future<List<SavedTitleRef>> list(WatchStatus status) async {
    await _historyWrites;
    final entries = await _listEntries();
    return entries.values
        .where((e) => e.status == status.value)
        .map((e) => e.title)
        .toList();
  }

  static Future<void> clearLists() => _mutateHistory(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_listsKey);
    revision.value++;
  });

  // ---------------------------------------------------------------- ratings

  static Future<Map<String, int>> _ratings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ratingsKey);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, int>{
          for (final e in decoded.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
        };
      }
    } catch (_) {
      // fall through
    }
    return <String, int>{};
  }

  /// The user's own 1–5 score for a title, if they set one.
  static Future<int?> rating(String id) async {
    await _historyWrites;
    final all = await _ratings();
    final key = await workId(id);
    if (all.containsKey(key)) return all[key];
    if (all.containsKey(id)) return all[id];
    final prefs = await SharedPreferences.getInstance();
    final aliases = _aliases(prefs);
    for (final entry in all.entries) {
      if (_resolveKey(entry.key, aliases) == key) return entry.value;
    }
    return null;
  }

  static Future<void> setRating(String id, int? stars) => _mutateHistory(() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _ratings();
    final aliases = _aliases(prefs);
    final key = _resolveKey(id, aliases);
    all.removeWhere((other, _) => _resolveKey(other, aliases) == key);
    if (stars == null || stars <= 0) {
      all.remove(key);
    } else {
      all[key] = stars.clamp(1, 5).toInt();
    }
    await prefs.setString(_ratingsKey, jsonEncode(all));
    revision.value++;
  });

  static Future<void> clearRatings() => _mutateHistory(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ratingsKey);
    revision.value++;
  });

  // -------------------------------------------------------------- statistics

  static Future<LibraryStats> stats() async {
    final entries = await history();
    final listEntries = await _listEntries();
    final favorites = await Library.favorites();

    var seconds = 0;
    for (final e in entries) {
      seconds += e.positionMs ~/ 1000;
    }
    final counts = <int, int>{};
    for (final e in listEntries.values) {
      counts[e.status] = (counts[e.status] ?? 0) + 1;
    }

    return LibraryStats(
      watchedEpisodes: entries.length,
      watchedSeconds: seconds,
      historySize: entries.length,
      favorites: favorites.length,
      listCounts: counts,
    );
  }

  // ---------------------------------------------------------- search history

  static Future<List<String>> searchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_searchKey) ?? <String>[];
  }

  static Future<void> rememberSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_searchKey) ?? <String>[];
    list.remove(q);
    list.insert(0, q);
    if (list.length > maxSearch) list.removeRange(maxSearch, list.length);
    await prefs.setStringList(_searchKey, list);
    revision.value++;
  }

  static Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchKey);
    revision.value++;
  }

  // -------------------------------------------------------------- my tab

  /// The saved "Моя вкладка" filter shown as the first Home tab.
  static Future<CatalogFilter?> myTabFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_myTabKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return CatalogFilter.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // fall through
    }
    return null;
  }

  static Future<void> setMyTabFilter(CatalogFilter? filter) async {
    final prefs = await SharedPreferences.getInstance();
    if (filter == null) {
      await prefs.remove(_myTabKey);
    } else {
      await prefs.setString(_myTabKey, jsonEncode(filter.toJson()));
    }
    revision.value++;
  }

  // ---------------------------------------------------------------- helpers

  static List<Map<String, dynamic>> _decodeList(List<String>? raw) {
    final out = <Map<String, dynamic>>[];
    for (final item in raw ?? const <String>[]) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) out.add(decoded.cast<String, dynamic>());
      } catch (_) {
        // Skip a corrupt entry rather than losing the whole list.
      }
    }
    return out;
  }
}
