import 'package:flutter/material.dart';

import '../favorites/favorites_controller.dart';
import '../favorites/favorites_page.dart';
import '../home/home_page.dart';
import '../lines/lines_page.dart';

class AppShellPage extends StatefulWidget {
  const AppShellPage({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  final bool isDarkMode;
  final Future<void> Function() onToggleTheme;

  @override
  State<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends State<AppShellPage>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final FavoritesController _favoritesController;

  @override
  void initState() {
    super.initState();
    _favoritesController = FavoritesController();
    _initializeFavorites();
  }

  Future<void> _initializeFavorites() async {
    try {
      await _favoritesController.initialize();
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _favoritesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomePage(
            favoritesController: _favoritesController,
            onOpenLines: () => setState(() => _currentIndex = 1),
            onOpenFavorites: () => setState(() => _currentIndex = 2),
          ),
          LinesPage(favoritesController: _favoritesController),
          FavoritesPage(
            favoritesController: _favoritesController,
            onToggleTheme: widget.onToggleTheme,
            isDarkMode: widget.isDarkMode,
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        isDark: isDark,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.isDark,
    required this.onTap,
  });

  final int currentIndex;
  final bool isDark;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F1722) : Colors.white;
    final border = isDark ? const Color(0xFF1F2937) : const Color(0xFFE8EDF5);
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = isDark ? const Color(0xFF6B7A8D) : const Color(0xFF94A3B8);

    final items = [
      _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Ana Sayfa'),
      _NavItem(icon: Icons.route_outlined, activeIcon: Icons.route_rounded, label: 'Hatlar'),
      _NavItem(icon: Icons.star_outline_rounded, activeIcon: Icons.star_rounded, label: 'Favoriler'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final isActive = currentIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? activeColor.withValues(alpha: isDark ? 0.15 : 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? item.activeIcon : item.icon,
                          color: isActive ? activeColor : inactiveColor,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                            color: isActive ? activeColor : inactiveColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}
