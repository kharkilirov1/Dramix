import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend_session.dart';
import '../../core/backend_sync.dart';
import '../../core/theme.dart';
import '../widgets.dart';

/// Optional server account. The active Library stays local after sign-in.
class AccountScreen extends StatefulWidget {
  final Uri origin;
  final BackendSession? session;
  const AccountScreen({super.key, required this.origin, this.session});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final BackendSession session =
      widget.session ?? BackendSession.forOrigin(widget.origin);
  late final BackendSync sync = BackendSync(session);
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _register = false;
  bool _obscure = true;
  bool _failed = false;
  int? _pending;
  int? _cloudCount;
  String _message = '';

  @override
  void initState() {
    super.initState();
    if (session.authenticated) _readStoredState();
  }

  // Read local metadata only. Opening this screen never sends an import/pull.
  Future<void> _readStoredState() async {
    if (!session.authenticated) {
      if (mounted) setState(() { _pending = null; _cloudCount = null; });
      return;
    }
    final actor = session.userId;
    final scope = 'dramix.cloud.v1.${Uri.encodeComponent(session.origin.toString())}.$actor';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$scope.pending');
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded != null && decoded is! List) {
        throw const FormatException('Invalid pending operations');
      }
      final snapshot = await sync.snapshot();
      final library = snapshot['library'];
      if (library is! Map) throw const FormatException('Invalid cloud snapshot');
      if (!mounted || !session.authenticated || session.userId != actor) return;
      setState(() {
        _pending = decoded == null ? 0 : (decoded as List).length;
        _cloudCount = prefs.containsKey('$scope.snapshot')
            ? library.values.where((v) => v is Map && v['deleted'] != true).length
            : null;
      });
    } catch (_) {
      if (!mounted || session.userId != actor) return;
      setState(() {
        _pending = null;
        _failed = true;
        _message = 'Не удалось прочитать состояние импорта. Данные устройства сохранены.';
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _message = ''; _failed = false; });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() {
        _failed = true;
        _message = error is BackendConflict
            ? '${error.message} Незавершённая операция сохранена. '
              'Повтор не перезапишет облачную запись.'
            : error is BackendError
                ? error.message
                : 'Действие не завершено. Проверьте соединение и повторите.';
      });
    } finally {
      await _readStoredState();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      await session.signIn(_name.text, _password.text, register: _register);
      _password.clear();
      _message = 'Вход выполнен. Локальные данные не отправлены на сервер.';
    });
  }

  Future<void> _importGuest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Скопировать библиотеку?'),
        content: const Text('Списки, избранное и корректные точки истории будут '
            'скопированы на этот сервер. Данные устройства останутся на месте.\n\n'
            'Существующие облачные записи и удаления не перезаписываются. '
            'Каждая дорама импортируется отдельно; при сбое часть импорта '
            'может быть уже завершена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Скопировать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      final count = await sync.importGuest();
      _message = count == 0
          ? 'Нет новых записей для импорта. Локальная библиотека сохранена.'
          : 'Скопировано записей: $count. Локальная библиотека сохранена.';
      if (sync.skippedHistoryPoints > 0) {
        _message += ' Пропущено точек без корректного сезона или серии: '
            '${sync.skippedHistoryPoints}.';
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    color: AppColors.surface,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Аккаунт сервера',
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.authenticated ? 'Аккаунт подключён' : 'Гостевой режим',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('История и списки остаются на этом устройстве. '
                    'Для просмотра вход не нужен.'),
                const SizedBox(height: 12),
                const Text('Сервер', style: TextStyle(color: AppColors.textSecondary)),
                SelectableText(widget.origin.toString()),
                if (session.authenticated) ...[
                  const SizedBox(height: 8),
                  Text('Пользователь: ${session.username ?? '—'}'),
                ],
              ])),
              if (!session.authenticated) _card(
                Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(_register ? 'Создать аккаунт' : 'Войти в аккаунт',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'Имя пользователя',
                            helperText: '3–40 символов: латиница, цифры, _ . -'),
                        validator: (value) => RegExp(r'^[A-Za-z0-9_.-]{3,40}$')
                            .hasMatch((value ?? '').trim())
                            ? null : 'Введите имя из 3–40 допустимых символов',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        enableSuggestions: false,
                        autocorrect: false,
                        autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) { if (!_busy) _signIn(); },
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          helperText: 'От 12 до 256 символов',
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
                            onPressed: _busy ? null : () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (value) => value != null && value.length >= 12 && value.length <= 256
                            ? null : 'Пароль должен содержать 12–256 символов',
                      ),
                      const SizedBox(height: 20),
                      FilledButton(onPressed: _busy ? null : _signIn,
                          child: Text(_register ? 'Создать аккаунт' : 'Войти')),
                      TextButton(
                        onPressed: _busy ? null : () => setState(() {
                          _register = !_register; _message = '';
                          _form.currentState?.reset();
                        }),
                        child: Text(_register ? 'Уже есть аккаунт? Войти' : 'Создать новый аккаунт'),
                      ),
                    ]),
                  ),
                ),
              ) else _card(
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Облачная библиотека', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_cloudCount == null ? 'Ещё не проверена' :
                      _cloudCount == 0 ? 'В сохранённом облачном снимке пока пусто' :
                      'Записей в сохранённом снимке: $_cloudCount'),
                  const SizedBox(height: 8),
                  const Text('Проверка обновляет облачный снимок, но не заменяет '
                      'локальную историю и списки.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(() async {
                      await sync.pull();
                      _message = 'Облачные данные проверены. Локальная библиотека не изменена.';
                    }),
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Проверить облачную библиотеку'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _importGuest,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Скопировать локальную библиотеку'),
                  ),
                  const SizedBox(height: 16),
                  Text(_pending == null ? 'Состояние незавершённых операций неизвестно' :
                      _pending == 0 ? 'Незавершённых операций нет' : 'Ожидают завершения: $_pending'),
                  TextButton(
                    onPressed: _busy || _pending == 0 ? null : () => _run(() async {
                      final count = await sync.retryPending();
                      _message = 'Завершено ожидающих операций: $count.';
                    }),
                    child: const Text('Повторить незавершённый импорт'),
                  ),
                  const Divider(),
                  TextButton(
                    onPressed: _busy ? null : () => _run(() async {
                      await session.logout();
                      _message = 'Вы вышли. Локальные данные сохранены.';
                    }),
                    child: const Text('Выйти из аккаунта'),
                  ),
                ]),
              ),
              if (_busy) const Semantics(
                label: 'Выполняется действие',
                child: LinearProgressIndicator(),
              ),
              if (_message.isNotEmpty) Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_message, style: TextStyle(
                      color: _failed ? Theme.of(context).colorScheme.error : AppColors.textPrimary)),
                ),
              ),
              const Text('Автоматическая синхронизация пока не включена. '
                  'Облачные данные не применяются к локальной библиотеке. '
                  'После перезапуска потребуется войти снова.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    ),
  );
}
