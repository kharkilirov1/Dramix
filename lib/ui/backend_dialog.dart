import 'package:flutter/material.dart';

import '../core/net.dart';

/// Empty input restores the existing direct/proxy guest route.
Future<bool> configureBackend(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
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
    return AlertDialog(
      title: const Text('Свой сервер каталога'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Укажите адрес своего сервера Dramix. '
              'Оставьте поле пустым для обычного подключения. '
              'Это меняет только каталог; история остаётся на устройстве.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
                hintText: 'https://dramix.example', errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Отмена')),
        TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Сохранить')),
      ],
    );
  }
}
