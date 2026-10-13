import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Public reads are episode-scoped; writes never automatically retry.
class BackendComments {
  BackendComments({required this.origin, required this.token,
    required this.userId, http.Client? client})
      : _client = client ?? http.Client(), _ownsClient = client == null;
  final Uri origin;
  final String? Function() token;
  final String? Function() userId;
  final http.Client _client;
  final bool _ownsClient;
  bool get authenticated => token()?.isNotEmpty == true && userId() != null;

  static String operationKey() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (origin.host.isEmpty || origin.userInfo.isNotEmpty || origin.hasQuery || origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        !(origin.scheme == 'https' || (origin.scheme == 'http' &&
          ['localhost', '127.0.0.1', '::1'].contains(origin.host)))) {
      throw const CommentsError(null, 'Недопустимый адрес сервера.');
    }
    return origin.replace(path: path, queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, String>? query, Map<String, dynamic>? body,
       CommentOperation? operation}) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Content-Type'] = 'application/json';
    if (operation != null) {
      final currentToken = token();
      if (currentToken == null || currentToken.isEmpty ||
          userId() != operation.ownerId) {
        throw const CommentsError(401, 'Войдите в тот же аккаунт для повтора.');
      }
      request.headers['Authorization'] = 'Bearer $currentToken';
      request.headers['Idempotency-Key'] = operation.key;
    }
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 12)))
        .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CommentsError(response.statusCode, switch (response.statusCode) {
          401 => 'Сессия истекла. Войдите снова.',
          403 => 'Нет доступа к этому действию.',
          409 => 'Конфликт запроса. Обновите комментарии.',
          400 => 'Проверьте текст и параметры комментария.',
          404 => 'Комментарий не найден.',
          _ => 'Сервер недоступен. Попробуйте повторить.',
        });
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } on CommentsError { rethrow; }
    catch (_) {
      throw const CommentsError(null, 'Не удалось получить ответ. Можно повторить запрос.');
    }
  }

  Future<CommentPage> read({required String workKey, required int season,
      required int episode, int after = 0, bool revealSpoilers = false}) async {
    final data = await _request('GET', '/v1/comments', query: {
      'work_key': workKey, 'season': '$season', 'episode': '$episode',
      'after': '$after', 'limit': '50', 'reveal_spoilers': '$revealSpoilers',
    });
    return CommentPage(
      (data['items'] as List).map((e) => EpisodeComment.fromJson(
        Map<String, dynamic>.from(e as Map))).toList(),
      (data['cursor'] as num).toInt(), data['has_more'] == true);
  }

  CommentOperation operation(String method, String path, Map<String, dynamic> body) {
    final owner = userId();
    if (!authenticated || owner == null) {
      throw const CommentsError(401, 'Для этого действия войдите в аккаунт.');
    }
    return CommentOperation._(method, path,
      Map<String, dynamic>.unmodifiable(body), operationKey(), owner);
  }

  CommentOperation create({required String workKey, required int season,
      required int episode, required String text, required bool spoiler}) =>
    operation('POST', '/v1/comments', {'work_key': workKey, 'season': season,
      'episode': episode, 'text': text.trim(), 'spoiler': spoiler});
  CommentOperation edit(EpisodeComment comment, String text, bool spoiler) {
    _owner(comment);
    return operation('PATCH', '/v1/comments/${comment.id}',
      {'text': text.trim(), 'spoiler': spoiler});
  }
  CommentOperation delete(EpisodeComment comment) {
    _owner(comment);
    return operation('DELETE', '/v1/comments/${comment.id}', {});
  }
  CommentOperation report(EpisodeComment comment, String reason) =>
    operation('POST', '/v1/comments/${comment.id}/report', {'reason': reason.trim()});
  void _owner(EpisodeComment comment) {
    if (comment.authorId != userId() || comment.deleted) {
      throw const CommentsError(403, 'Редактировать может только автор.');
    }
  }
  Future<void> submit(CommentOperation operation) async {
    await _request(operation.method, operation.path,
      body: operation.body, operation: operation);
  }
  void close() { if (_ownsClient) _client.close(); }
}

class CommentOperation {
  const CommentOperation._(this.method, this.path, this.body, this.key, this.ownerId);
  final String method, path, key, ownerId;
  final Map<String, dynamic> body;
}
class CommentsError implements Exception {
  const CommentsError(this.status, this.message);
  final int? status;
  final String message;
  @override
  String toString() => message;
}
class CommentPage {
  const CommentPage(this.items, this.cursor, this.hasMore);
  final List<EpisodeComment> items;
  final int cursor;
  final bool hasMore;
}
class EpisodeComment {
  const EpisodeComment({required this.id, required this.author,
    required this.authorId, required this.text, required this.spoiler,
    required this.deleted});
  factory EpisodeComment.fromJson(Map<String, dynamic> data) => EpisodeComment(
    id: (data['id'] as num).toInt(), author: data['author'] as String,
    authorId: '${data['author_id']}', text: data['text'] as String?,
    spoiler: data['spoiler'] == true, deleted: data['deleted'] == true);
  final int id;
  final String author, authorId;
  final String? text;
  final bool spoiler, deleted;
}
