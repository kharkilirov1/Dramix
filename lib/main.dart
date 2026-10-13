import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/kodik_api.dart';
import 'core/kodik_token.dart';
import 'core/net.dart';
import 'core/premium.dart';
import 'core/theme.dart';
import 'ui/collections/collections_screen.dart';
import 'ui/filter/filter_screen.dart';
import 'ui/notifications/notifications_screen.dart';
import 'ui/popular/popular_screen.dart';
import 'ui/root.dart';
import 'ui/schedule/schedule_screen.dart';
import 'ui/search/search_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  // Routing must be known before the first request: web needs a CORS proxy.
  await Net.load();
  await Premium.load();
  runApp(const DramixApp());
}

class DramixApp extends StatelessWidget {
  const DramixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dramix',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routes: <String, WidgetBuilder>{
        Routes.search: (_) => const SearchScreen(),
        Routes.settings: (_) => const SettingsScreen(),
        Routes.notifications: (_) => const NotificationsScreen(),
        Routes.popular: (_) => const PopularScreen(),
        Routes.schedule: (_) => const ScheduleScreen(),
        Routes.collections: (_) => const CollectionsScreen(),
        Routes.filter: (_) => const FilterScreen(),
      },
      home: const AppGate(),
    );
  }
}

/// Resolves a working Kodik token before mounting the shell, so the first
/// catalog request never races token discovery.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await KodikApi.instance.tokens.ensure();
      if (mounted) setState(() => _loading = false);
    } on KodikTokenException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _enterToken() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Токен Kodik'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(hintText: '32 hex-символа'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    try {
      final ok = await KodikApi.instance.tokens.setUserToken(value);
      if (!mounted) return;
      if (ok) {
        await _boot();
      } else {
        showMessage(context, 'Токен не подошёл');
      }
    } on KodikTokenException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Splash();
    if (_error != null) {
      return _TokenError(
          message: _error!, onRetry: _boot, onEnterToken: _enterToken);
    }
    return const RootShell();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_movies_rounded, size: 54, color: AppColors.light),
            SizedBox(height: 16),
            Text('Dramix',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            SizedBox(height: 26),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.textSecondary),
            ),
            SizedBox(height: 14),
            Text('Подключаемся к Kodik…',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _TokenError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onEnterToken;

  const _TokenError({
    required this.message,
    required this.onRetry,
    required this.onEnterToken,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.key_off_rounded,
                    size: 46, color: AppColors.textTertiary),
                const SizedBox(height: 16),
                const Text('Нет доступа к Kodik',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 22),
                LightPillButton(label: 'Попробовать снова', onTap: onRetry),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onEnterToken,
                  child: const Text('Ввести свой токен'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
