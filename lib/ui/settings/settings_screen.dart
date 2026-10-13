import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/kodik_token.dart';
import '../../core/net.dart';
import '../../core/premium.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../premium/paywall_screen.dart';
import '../widgets.dart';

/// Настройки (эталон: screenshot 09) — секции с иконками, доступ к Kodik,
/// локальные данные и сведения о приложении.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _forceBusy = false;
  bool _userTokenSet = false;

  @override
  void initState() {
    super.initState();
    KodikTokenStore.revision.addListener(_onRevision);
    Net.revision.addListener(_onRevision);
    Premium.revision.addListener(_onRevision);
    _loadUserToken();
    if (!KodikApi.instance.tokens.hasToken) {
      _busy = true;
      _resolveToken();
    }
  }

  @override
  void dispose() {
    KodikTokenStore.revision.removeListener(_onRevision);
    Net.revision.removeListener(_onRevision);
    Premium.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUserToken() async {
    final token = await KodikApi.instance.tokens.userToken();
    if (!mounted) return;
    setState(() => _userTokenSet = token != null);
  }

  Future<void> _resolveToken() async {
    try {
      await KodikApi.instance.tokens.ensure();
    } on KodikTokenException {
      // Сообщение покажет строка статуса; отдельный snackbar не нужен.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _maskedToken {
    final token = KodikApi.instance.tokens.token ?? '';
    if (token.length <= 10) return token;
    return '${token.substring(0, 6)}…${token.substring(token.length - 4)}';
  }

  String get _tokenSubtitle => KodikApi.instance.tokens.hasToken
      ? 'Активен · $_maskedToken'
      : 'Не найден';

  String get _userTokenSubtitle =>
      _userTokenSet ? 'Задан' : 'Не задан — используется общий пул';

  Future<void> _refreshToken() async {
    setState(() => _forceBusy = true);
    try {
      await KodikApi.instance.tokens.ensure(forceRefresh: true);
      if (mounted) showMessage(context, 'Токен обновлён');
    } on KodikTokenException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _forceBusy = false);
    }
  }

  Future<void> _askUserToken() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _TokenDialog(),
    );
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await KodikApi.instance.tokens.setUserToken(null);
      if (!mounted) return;
      setState(() => _userTokenSet = false);
      showMessage(context, 'Пользовательский токен удалён');
      return;
    }
    final ok = await KodikApi.instance.tokens.setUserToken(trimmed);
    if (!mounted) return;
    if (ok) setState(() => _userTokenSet = true);
    showMessage(context, ok ? 'Токен принят' : 'Токен не подошёл');
  }

  Future<void> _confirm(String title, String message, Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Очистить')),
        ],
      ),
    );
    if (ok != true) return;
    await run();
    if (!mounted) return;
    showMessage(context, 'Готово');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SizedBox(height: 8),
            _heading('ПОДПИСКА'),
            _tile(
              icon: Icons.workspace_premium_rounded,
              title: Premium.isPremium ? 'Dramix Plus активен' : 'Dramix Plus',
              subtitle: _premiumSubtitle,
              trailing: Icon(
                Premium.isPremium ? Icons.verified_rounded : Icons.chevron_right,
                size: 20,
                color: Premium.isPremium
                    ? AppColors.statPlans
                    : AppColors.textTertiary,
              ),
            ),
            _action(
              icon: Icons.workspace_premium_outlined,
              title: Premium.isPremium
                  ? 'Управление подпиской'
                  : 'Открыть Dramix Plus',
              subtitle: 'Расширенные фильтры, история до 200 записей, подборки',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const PaywallScreen()),
                );
                if (mounted) setState(() {});
              },
            ),
            _heading('ДОСТУП К KODIK'),
            _tile(
              icon: Icons.vpn_key_outlined,
              title: 'Текущий токен',
              subtitle: _tokenSubtitle,
              trailing: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textSecondary))
                  : Icon(
                      KodikApi.instance.tokens.hasToken
                          ? Icons.check_circle
                          : Icons.error_outline,
                      size: 20,
                      color: KodikApi.instance.tokens.hasToken
                          ? AppColors.statWatching
                          : AppColors.badgeNew),
            ),
            _action(
              icon: Icons.autorenew,
              title: 'Обновить токен',
              subtitle: 'Пройти по пулу заново и проверить каждый',
              onTap: _forceBusy ? null : _refreshToken,
            ),
            _action(
              icon: Icons.edit_outlined,
              title: 'Ввести свой токен',
              subtitle: _userTokenSubtitle,
              onTap: _askUserToken,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                'Kodik не выдаёт токены публично. Приложение проверяет несколько '
                'источников и использует первый рабочий, поэтому обычно ничего '
                'вводить не нужно.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiary, height: 1.45),
              ),
            ),
            _heading('СЕТЬ'),
            _tile(
              icon: Net.isDirect ? Icons.wifi : Icons.alt_route,
              title: 'Маршрут запросов',
              subtitle: _netSubtitle,
              trailing: Icon(
                Net.isDirect ? Icons.check_circle : Icons.shield_outlined,
                size: 20,
                color: Net.isDirect
                    ? AppColors.statWatching
                    : AppColors.textSecondary,
              ),
            ),
            _action(
              icon: Icons.alt_route,
              title: 'Выбрать маршрут',
              subtitle: 'Прямое подключение или CORS-прокси',
              onTap: _chooseRoute,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text(
                'Kodik не отдаёт CORS-заголовки, поэтому браузер не может обратиться '
                'к API напрямую: веб-сборка по умолчанию идёт через прокси. '
                'На Android, iOS, Windows и macOS прокси не нужен.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textTertiary, height: 1.45),
              ),
            ),
            _heading('ДАННЫЕ'),
            _action(
              icon: Icons.history,
              title: 'Очистить историю просмотра',
              subtitle: 'Удаляет все локальные записи о просмотре',
              onTap: () => _confirm('Очистить историю?',
                  'История просмотра будет удалена без возможности восстановления.',
                  Library.clearHistory),
            ),
            _action(
              icon: Icons.favorite_border,
              title: 'Очистить избранное',
              subtitle: 'Удаляет все сохранённые тайтлы',
              onTap: () => _confirm('Очистить избранное?',
                  'Все сохранённые тайтлы будут удалены.', Library.clearFavorites),
            ),
            _action(
              icon: Icons.bookmark_border,
              title: 'Очистить списки',
              subtitle: 'Смотрю · В планах · Просмотрено · Отложено · Брошено',
              onTap: () => _confirm('Очистить списки?',
                  'Все списки просмотра будут удалены.', Library.clearLists),
            ),
            _action(
              icon: Icons.search_off,
              title: 'Очистить историю поиска',
              subtitle: 'Удаляет сохранённые поисковые запросы',
              onTap: () => _confirm('Очистить историю поиска?',
                  'Сохранённые запросы будут удалены.', Library.clearSearchHistory),
            ),
            _heading('О ПРИЛОЖЕНИИ'),
            _tile(
              icon: Icons.movie_outlined,
              title: 'Dramix 1.0.0',
              subtitle: 'Клиент дорам, сериалов и фильмов',
            ),
            _tile(
              icon: Icons.public,
              title: 'Каталог',
              subtitle: 'kodik-api.com',
            ),
            _tile(
              icon: Icons.play_circle_outline,
              title: 'Плеер',
              subtitle: 'kodikplayer.com + нативный HLS',
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textTertiary)),
      );

  String get _premiumSubtitle {
    if (!Premium.isPremium) {
      return 'Фильтры по стране, жанрам и рейтингу';
    }
    if (Premium.isLifetime) return 'Навсегда, без продления';
    return 'Осталось дней: ${Premium.daysLeft ?? 0}';
  }

  String get _netSubtitle => switch (Net.mode) {
        NetMode.direct => 'Напрямую · kodik-api.com',
        NetMode.wrap => 'CORS-прокси · ${_shortHost(Net.template)}',
        NetMode.prefix => 'Префикс-прокси · ${_shortHost(Net.template)}',
      };

  static String _shortHost(String template) {
    final host = Uri.tryParse(template)?.host ?? '';
    return host.isEmpty ? template : host;
  }

  Future<void> _chooseRoute() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('Маршрут запросов',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('Напрямую'),
            subtitle: const Text(
                'Где нет CORS: Android, iOS, Windows, macOS',
                style: TextStyle(fontSize: 12.5)),
            trailing: Net.mode == NetMode.direct
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () => Navigator.pop(context, 'direct'),
          ),
          ListTile(
            leading: const Icon(Icons.alt_route),
            title: const Text('CORS-прокси'),
            subtitle: Text(_shortHost(Net.allOrigins),
                style: const TextStyle(fontSize: 12.5)),
            trailing:
                Net.mode == NetMode.wrap ? const Icon(Icons.check_rounded) : null,
            onTap: () => Navigator.pop(context, 'wrap'),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('По умолчанию для платформы'),
            onTap: () => Navigator.pop(context, 'reset'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'direct':
        await Net.set(mode: NetMode.direct, template: Net.template);
        break;
      case 'wrap':
        await Net.set(mode: NetMode.wrap, template: Net.allOrigins);
        break;
      case 'reset':
        await Net.resetToDefault();
        break;
    }
    if (!mounted) return;
    setState(() {});
    showMessage(context, 'Маршрут обновлён');
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(icon, size: 22, color: AppColors.textSecondary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textTertiary)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _action({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(icon, size: 22, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textTertiary)),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 20, color: AppColors.textTertiary),
        ]),
      ),
    );
  }
}

/// Диалог ручного ввода токена. Владеет своим [TextEditingController].
class _TokenDialog extends StatefulWidget {
  const _TokenDialog();

  @override
  State<_TokenDialog> createState() => _TokenDialogState();
}

class _TokenDialogState extends State<_TokenDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Свой токен Kodik'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
            hintText: '32 hex-символа',
            hintStyle: TextStyle(color: AppColors.textTertiary)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        TextButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Сохранить')),
      ],
    );
  }
}
