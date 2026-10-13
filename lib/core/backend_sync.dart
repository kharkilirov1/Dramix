import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'backend_session.dart';
import 'storage.dart';

/// Explicit cloud snapshots and guest upload. Does not replace guest Library,
/// schedule background work, or claim a bidirectional offline sync engine.
class BackendSync {
  final BackendSession session;
  BackendSync(this.session);
  String get _scope {
    if (!session.authenticated) throw const BackendError(401, 'Войдите в аккаунт.');
    return 'dramix.cloud.v1.${Uri.encodeComponent(session.origin.toString())}.${session.userId}';
  }
  String _key(String suffix) => '$_scope.$suffix';
  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, jsonEncode(value))) {
      throw StateError('Unable to persist cloud operation');
    }
  }
  Future<Map<String, dynamic>> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key('snapshot'));
    if (raw == null) return {'library': {}, 'checkpoints': {}};
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }
  /// Both independent feeds are fully paginated before one snapshot is saved.
  /// Restarting from zero avoids incomplete cursor commits after interruption.
  Future<Map<String, dynamic>> pull() async {
    final scope = _scope;
    final library = <String, dynamic>{};
    final checkpoints = <String, dynamic>{};
    for (final feed in ['library', 'checkpoints']) {
      var cursor = 0;
      var pages = 0;
      while (true) {
        if (++pages > 10000) throw const FormatException('Too many pages');
        final page = await session.request('GET', '/v1/$feed',
            query: {'after': '$cursor', 'limit': '100'});
        if (_scope != scope) throw StateError('Account changed during sync');
        if (page['items'] is! List || page['cursor'] is! int ||
            page['has_more'] is! bool) throw const FormatException('Invalid feed');
        for (final raw in page['items'] as List) {
          final item = (raw as Map).cast<String, dynamic>();
          final work = item['work_key'];
          if (work is! String || item['revision'] is! int ||
              item['deleted'] is! bool) throw const FormatException('Invalid item');
          final target = feed == 'library' ? library : checkpoints;
          final key = feed == 'library' ? work :
              '$work:${item['season']}:${item['episode']}';
          final previous = target[key] as Map?;
          if (previous == null ||
              (item['revision'] as int) > (previous['revision'] as int)) target[key] = item;
        }
        final next = page['cursor'] as int;
        if (page['has_more'] == true && next <= cursor) {
          throw const FormatException('Non advancing cursor');
        }
        cursor = next;
        if (page['has_more'] == false) break;
      }
    }
    final result = {'library': library, 'checkpoints': checkpoints};
    await _save('$scope.snapshot', result);
    return result;
  }

  /// Only new server works are eligible for guest import. Existing records and
  /// tombstones require deliberate reconciliation, never a guessed revision.
  Future<int> importGuest() async {
    final scope = _scope;
    final prefs = await SharedPreferences.getInstance();
    final pendingKey = '$scope.pending';
    if (prefs.containsKey(pendingKey)) return retryPending();
    await pull();
    final remote = (await snapshot())['library'] as Map;
    final bodies = <String, Map<String, dynamic>>{};
    Map<String, dynamic> body(String work) => bodies.putIfAbsent(work, () =>
        {'work_key': work, 'base_revision': 0});
    String canonical(String id) => RegExp(
        r'^(kinopoisk|imdb|mdl|shikimori|kodik):').hasMatch(id) ? id : 'kodik:$id';
    final history = await Library.history();
    for (final title in await Library.favorites()) {
      final b = body(canonical(await Library.workId(title.id)));
      b['favorite'] = true;
      final rating = await Library.rating(title.id);
      if (rating != null) b['rating'] = rating;
    }
    const statuses = ['watching', 'plans', 'completed', 'hold', 'dropped'];
    for (final status in WatchStatus.values) {
      for (final title in await Library.list(status)) {
        final b = body(canonical(await Library.workId(title.id)));
        b['status'] = statuses[status.value - 1];
        final rating = await Library.rating(title.id);
        if (rating != null) b['rating'] = rating;
      }
    }
    for (final point in history) {
      final work = canonical(await Library.workId(point.title.id));
      final b = body(work);
      final rating = await Library.rating(point.title.id);
      if (rating != null) b['rating'] = rating;
      if (point.season == null || point.episode == null ||
          point.season! < 1 || point.episode! < 1 || point.positionMs < 0) continue;
      final checkpoint = {
        'season': point.season, 'episode': point.episode,
        'position_ms': point.positionMs, 'variant_id': point.title.id,
      };
      final points = (b['checkpoints'] ??= <Map<String, dynamic>>[])
          as List<Map<String, dynamic>>;
      if (!points.any((p) => p['season'] == point.season &&
          p['episode'] == point.episode)) points.add(checkpoint);
      // Library history is most-recent-first; no resume from episode numbering.
      b.putIfAbsent('progress', () => checkpoint);
    }
    for (final work in bodies.keys) {
      if (remote.containsKey(work)) throw BackendConflict(work);
      final points = bodies[work]!['checkpoints'] as List?;
      if (points != null && points.length > 100) {
        throw BackendError(400, 'Более 100 точек истории для $work: импорт не выполнен.');
      }
    }
    if (_scope != scope) throw StateError('Account changed during import');
    // Exact original guest keys copied once; never removed or rewritten.
    final backupKey = '$scope.guestBackup';
    if (!prefs.containsKey(backupKey)) {
      await _save(backupKey, {
        for (final key in ['dramix.history', 'dramix.favorites', 'dramix.lists',
          'dramix.ratings', 'dramix.workAliases.v1'])
          if (prefs.containsKey(key)) key: prefs.get(key),
      });
    }
    final random = Random.secure();
    final pending = [
      for (final b in bodies.values) {
        'key': List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join(),
        'body': b,
      }
    ];
    await _save(pendingKey, pending);
    return retryPending();
  }

  /// Identical stored body/key survives transport failures. A 409 keeps the
  /// operation pending and surfaces conflict; revisions are never auto-rebased.
  Future<int> retryPending() async {
    final scope = _scope;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$scope.pending');
    if (raw == null) return 0;
    final pending = (jsonDecode(raw) as List).cast<Map>();
    var completed = 0;
    while (pending.isNotEmpty) {
      final op = pending.first;
      final body = (op['body'] as Map).cast<String, dynamic>();
      try {
        await session.request('PATCH', '/v1/library', body: body,
            operationKey: op['key'] as String);
      } on BackendError catch (error) {
        if (error.status == 409) throw BackendConflict(body['work_key'] as String);
        rethrow;
      }
      if (_scope != scope) throw StateError('Account changed during import');
      pending.removeAt(0);
      await _save('$scope.pending', pending);
      completed++;
    }
    await pull();
    return completed;
  }
}
