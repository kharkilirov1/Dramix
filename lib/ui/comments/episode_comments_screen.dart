import 'package:flutter/material.dart';
import '../../core/backend_comments.dart';

/// Pass null api when no owned server is configured. Caller owns the SDK.
class EpisodeCommentsScreen extends StatefulWidget {
  const EpisodeCommentsScreen({super.key, required this.api,
    required this.workKey, required this.season, required this.episode, this.onSignIn});
  final BackendComments? api;
  final String workKey;
  final Future<void> Function()? onSignIn;
  final int season, episode;
  @override
  State<EpisodeCommentsScreen> createState() => _EpisodeCommentsScreenState();
}

class _EpisodeCommentsScreenState extends State<EpisodeCommentsScreen> {
  final _items = <EpisodeComment>[];
  final _revealed = <int>{};
  int _cursor = 0;
  bool _more = false, _loading = false, _writing = false;
  String? _error;
  CommentOperation? _pending;

  @override
  void initState() { super.initState(); _load(reset: true); }

  Future<void> _load({bool reset = false}) async {
    final api = widget.api;
    if (api == null || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final page = await api.read(workKey: widget.workKey,
        season: widget.season, episode: widget.episode,
        after: reset ? 0 : _cursor);
      if (!mounted) return;
      setState(() {
        if (reset) { _items.clear(); _revealed.clear(); }
        _items.addAll(page.items);
        _cursor = page.cursor; _more = page.hasMore;
      });
    } on CommentsError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось прочитать комментарии.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reveal(EpisodeComment comment) async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Server reveals a page only after an explicit gesture. Keep only the
      // requested comment, never reveal neighboring spoiler bodies in the UI.
      final page = await widget.api!.read(workKey: widget.workKey,
        season: widget.season, episode: widget.episode,
        after: comment.id - 1, revealSpoilers: true);
      if (!mounted) return;
      final matches = page.items.where((e) => e.id == comment.id);
      if (matches.isNotEmpty) {
        setState(() {
          final index = _items.indexWhere((e) => e.id == comment.id);
          if (index >= 0) _items[index] = matches.first;
          _revealed.add(comment.id);
        });
      }
    } on CommentsError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось прочитать комментарий.');
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _submit(CommentOperation operation) async {
    if (_writing) return;
    setState(() { _pending = operation; _writing = true; _error = null; });
    try {
      await widget.api!.submit(operation);
      if (!mounted) return;
      setState(() => _pending = null);
      await _load(reset: true);
    } on CommentsError catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        // Retain exact body/key only for ambiguous transport/server failures.
        if (e.status != null && e.status! < 500) _pending = null;
      });
    } finally { if (mounted) setState(() => _writing = false); }
  }

  Future<void> _compose({EpisodeComment? comment, bool report = false}) async {
    if (_pending != null || _writing) return;
    final controller = TextEditingController(text: report ? '' : comment?.text ?? '');
    bool spoiler = comment?.spoiler ?? false;
    final result = await showDialog<({String text, bool spoiler})>(
      context: context, builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(report ? 'Пожаловаться' : comment == null ? 'Комментарий' : 'Редактировать'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, maxLines: 5,
                maxLength: report ? 500 : 3000,
                decoration: InputDecoration(hintText: report ? 'Причина жалобы' : 'Текст комментария')),
              if (!report) CheckboxListTile(value: spoiler, title: const Text('Содержит спойлер'),
                onChanged: (v) => update(() => spoiler = v ?? false)),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            TextButton(onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, (text: text, spoiler: spoiler));
            }, child: const Text('Отправить')),
          ],
        )));
    controller.dispose();
    if (result == null || !mounted) return;
    try {
      final api = widget.api!;
      final operation = report ? api.report(comment!, result.text)
        : comment != null ? api.edit(comment, result.text, result.spoiler)
        : api.create(workKey: widget.workKey, season: widget.season,
          episode: widget.episode, text: result.text, spoiler: result.spoiler);
      await _submit(operation);
    } on CommentsError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete(EpisodeComment comment) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (context) => AlertDialog(title: const Text('Удалить комментарий?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ]));
    if (confirmed != true || !mounted) return;
    try { await _submit(widget.api!.delete(comment)); }
    on CommentsError catch (e) { setState(() => _error = e.message); }
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final canWrite = api?.authenticated == true && !_writing && _pending == null;
    return Scaffold(
      appBar: AppBar(title: Text('Сезон ${widget.season} · серия ${widget.episode}')),
      body: api == null ? const Center(child: Padding(padding: EdgeInsets.all(24),
        child: Text('Комментарии доступны после подключения собственного сервера.')))
        : Column(children: [
          if (_loading || _writing) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_pending != null) Wrap(spacing: 8, children: [
            TextButton(onPressed: _writing ? null : () => _submit(_pending!),
              child: const Text('Повторить тот же запрос')),
            TextButton(onPressed: _writing ? null : () => setState(() => _pending = null),
              child: const Text('Отменить повтор')),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(onPressed: _loading ? null : () => _load(reset: true),
              child: const Text('Обновить')),
            TextButton(onPressed: canWrite ? () => _compose() : null,
              child: const Text('Написать')),
          ]),
          if (!api.authenticated) const Padding(padding: EdgeInsets.all(8),
            child: Text('Для публикации войдите в аккаунт своего сервера.')),
          if (!api.authenticated && widget.onSignIn != null)
            TextButton(onPressed: () async {
              await widget.onSignIn!();
              if (mounted) setState(() {});
            }, child: const Text('Войти')),
          Expanded(child: ListView(
            children: [
              if (_items.isEmpty && !_loading && _error == null)
                const ListTile(title: Text('Пока нет комментариев.')),
              for (final comment in _items) Card(child: Padding(
                padding: const EdgeInsets.all(12), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(comment.author, style: Theme.of(context).textTheme.titleSmall),
                    if (comment.deleted) const Text('Комментарий удалён')
                    else if (comment.spoiler && !_revealed.contains(comment.id))
                      TextButton(onPressed: _loading ? null : () => _reveal(comment),
                        child: const Text('Показать спойлер'))
                    else Text(comment.text ?? 'Текст недоступен'),
                    if (!comment.deleted && api.authenticated) Wrap(children: [
                      if (comment.authorId == api.userId()) ...[
                        TextButton(onPressed: canWrite && comment.text != null &&
                          (!comment.spoiler || _revealed.contains(comment.id))
                          ? () => _compose(comment: comment) : null,
                          child: const Text('Изменить')),
                        TextButton(onPressed: canWrite ? () => _delete(comment) : null,
                          child: const Text('Удалить')),
                      ],
                      TextButton(onPressed: canWrite ? () => _compose(comment: comment, report: true) : null,
                        child: const Text('Пожаловаться')),
                    ]),
                  ]))),
              if (_more) TextButton(onPressed: _loading ? null : () => _load(),
                child: const Text('Загрузить ещё')),
            ])),
        ]),
    );
  }
}
