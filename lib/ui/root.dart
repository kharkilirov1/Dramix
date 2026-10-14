import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/net.dart';
import 'bookmarks/bookmarks_screen.dart';
import 'discover/discover_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';

/// Root shell with the 4-tab bottom navigation:
/// Главная / Обзор / Закладки / Профиль.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Net.revision.addListener(_onNetworkChanged);
  }

  void _onNetworkChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Net.revision.removeListener(_onNetworkChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(
        key: ValueKey<int>(Net.revision.value),
        index: _tab,
        children: const [
          HomeScreen(),
          DiscoverScreen(),
          BookmarksScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selected: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _BottomNav({required this.selected, required this.onChanged});

  static const _items = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Главная'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Обзор'),
    (Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Закладки'),
    (Icons.account_circle_outlined, Icons.account_circle_rounded, 'Профиль'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64 + MediaQuery.textScalerOf(context).scale(12),
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: Semantics(
                    selected: selected == i,
                    button: true,
                    child: InkWell(
                      onTap: () => onChanged(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 34,
                            decoration: BoxDecoration(
                              color: selected == i
                                  ? AppColors.accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              selected == i ? _items[i].$2 : _items[i].$1,
                              size: 24,
                              color: selected == i
                                  ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _items[i].$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected == i
                                  ? FontWeight.w700 : FontWeight.w400,
                              color: selected == i
                                  ? AppColors.textPrimary : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top bar with rounded search field + settings + notifications,
/// visible on every tab.
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final String searchHint;
  final VoidCallback? onSearch;
  final int notificationBadge;

  const TopBar({
    super.key,
    required this.searchHint,
    this.onSearch,
    this.notificationBadge = 0,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onSearch,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(children: [
                  const Icon(Icons.search, size: 22, color: AppColors.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(searchHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textTertiary)),
                  ),
                ]),
              ),
            ),
            ),
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined,
                size: 26, color: AppColors.textSecondary),
            onPressed: () => Navigator.pushNamed(context, Routes.settings),
          ),
          Stack(
            children: [
              IconButton(
                tooltip: 'Обновления каталога',
                icon: const Icon(Icons.notifications_none_rounded,
                    size: 26, color: AppColors.textSecondary),
                onPressed: () => Navigator.pushNamed(context, Routes.notifications),
              ),
              if (notificationBadge > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: AppColors.badgeNew, shape: BoxShape.circle),
                    child: Text('$notificationBadge',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Route names used across the app.
class Routes {
  static const String search = '/search';
  static const String settings = '/settings';
  static const String notifications = '/notifications';
  static const String popular = '/popular';
  static const String schedule = '/schedule';
  static const String collections = '/collections';
  static const String collection = '/collection';
  static const String filter = '/filter';
  static const String release = '/release';
  static const String voiceover = '/voiceover';
}
