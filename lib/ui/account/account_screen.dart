import 'package:flutter/material.dart';
import '../../core/backend_session.dart';
import '../../core/backend_sync.dart';

/// Development account panel. Guest Library remains the active local library.
class AccountScreen extends StatefulWidget {
  final Uri origin;
  final BackendSession? session;
  const AccountScreen({super.key, required this.origin, this.session});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}
class _AccountScreenState extends State<AccountScreen> {
  late final BackendSession session = widget.session ?? BackendSession.forOrigin(widget.origin);
  late final BackendSync sync = BackendSync(session);
  final name = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String message = '';
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; message = ''; });
    try { await action(); }
    catch (error) {
      if (mounted) setState(() => message = error is BackendError
          ? error.message : 'Не удалось выполнить действие. Можно повторить.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> signIn(bool register) => run(() async {
    await session.signIn(name.text, password.text, register: register);
    password.clear();
    message = 'Вход выполнен. Данные устройства не изменены.';
  });
  Future<void> importGuest() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) =>
      AlertDialog(
        title: const Text('Импорт на сервер'),
        content: const Text('Скопировать локальные списки и историю? Данные устройства сохранятся. '
          'Существующие облачные записи и удаления не будут перезаписаны. '
          'Импорт выполняется отдельно для каждой дорамы.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Импортировать')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    await run(() async {
      final count = await sync.importGuest();
      message = 'Импортировано записей: $count. '
          'Пропущено точек без корректного сезона/серии: ${sync.skippedHistoryPoints}. '
          'Локальная библиотека сохранена.';
    });
  }
  @override
  void dispose() {
    name.dispose(); password.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Аккаунт сервера')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Сервер: ${widget.origin}'),
      const SizedBox(height: 12),
      const Text('Гостевой режим остаётся доступен. Вход не загружает историю автоматически. '
        'После перезапуска потребуется войти снова.'),
      const SizedBox(height: 16),
      if (!session.authenticated) ...[
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя пользователя'),
            enabled: !busy, autocorrect: false),
        TextField(controller: password, decoration: const InputDecoration(labelText: 'Пароль (от 12 символов)'),
            enabled: !busy, obscureText: true, enableSuggestions: false, autocorrect: false),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy ? null : () => signIn(false), child: const Text('Войти')),
        TextButton(onPressed: busy ? null : () => signIn(true), child: const Text('Создать аккаунт')),
      ] else ...[
        Text('Вы вошли: ${session.username}'),
        FilledButton(onPressed: busy ? null : () => run(() async {
          final snapshot = await sync.pull();
          final library = snapshot['library'] as Map;
          final active = library.values.where((v) => (v as Map)['deleted'] != true).length;
          message = 'Облачных записей: $active. Данные устройства не изменены.';
        }), child: const Text('Проверить облачную библиотеку')),
        OutlinedButton(onPressed: busy ? null : importGuest, child: const Text('Скопировать локальную библиотеку')),
        TextButton(onPressed: busy ? null : () => run(() async {
          final count = await sync.retryPending();
          message = 'Завершено ожидающих операций: $count.';
        }), child: const Text('Повторить незавершённый импорт')),
        TextButton(onPressed: busy ? null : () => run(() async {
          await session.logout(); message = 'Вы вышли. Данные устройства сохранены.';
        }), child: const Text('Выйти')),
      ],
      if (busy) const LinearProgressIndicator(),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(message)),
      const SizedBox(height: 16),
      const Text('Это прототип: автоматическая синхронизация и применение облачных данных '
        'в гостевую библиотеку не включены. Конфликты требуют отдельного решения.'),
    ]),
  );
}
