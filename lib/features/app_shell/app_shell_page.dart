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

class _AppShellPageState extends State<AppShellPage> {
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
    } catch (_) {
      // In widget tests or unsupported environments, continue without persistence.
    }
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _favoritesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomePage(
            favoritesController: _favoritesController,
            onOpenLines: () {
              setState(() {
                _currentIndex = 1;
              });
            },
            onOpenFavorites: () {
              setState(() {
                _currentIndex = 2;
              });
            },
          ),
          LinesPage(favoritesController: _favoritesController),
          FavoritesPage(favoritesController: _favoritesController),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Ana Sayfa',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Hatlar',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Favoriler',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'theme_toggle_fab',
        onPressed: () => widget.onToggleTheme(),
        tooltip: widget.isDarkMode ? 'Aydinlik moda gec' : 'Karanlik moda gec',
        child: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
      ),
    );
  }
}
