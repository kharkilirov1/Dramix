import 'package:flutter/material.dart';

import '../core/net.dart';

/// Empty input restores the existing direct/proxy guest route.
Future<bool> configureBackend(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _BackendDialog(),
  );
  return changed == true;
}

class _BackendDialog extends StatefulWidget {
  const _BackendDialog();

  @override
  State<_BackendDialog> createState() => _BackendDialogState();
}

class _BackendDialogState extends State<_BackendDialog> {
  final _controller = TextEditingController(
      text: Net.backendOrigin?.toString() ?? '');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Net.setBackend(_controller.text);
      if (mounted) Navigator.pop(context, true);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сохранить адрес');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
      scrollable: true,
      title: const Text('Свой сервер каталога'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Каталог будет загружаться через ваш сервер Dramix. '
              'Вход и перенос библиотеки выполняются отдельно в разделе аккаунта. '
              'Пустое поле возвращает обычное подключение к Kodik.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
                labelText: 'Адрес сервера',
                hintText: 'https://dramix.example',
                helperText: 'HTTPS-адрес без пути. Для разработки на этом '
                    'устройстве можно указать localhost.',
                helperMaxLines: 4,
                errorMaxLines: 4,
                errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Отмена')),
        TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Сохраняем…' : 'Сохранить')),
      ],
      ),
    );
  }
}
