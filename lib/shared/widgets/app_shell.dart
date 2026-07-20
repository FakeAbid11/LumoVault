import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Responsive shell that adapts navigation layout based on screen size.
///
/// - Phone (< 600px): Bottom navigation bar
/// - Tablet (600-840px): Navigation rail
/// - Large Tablet (> 840px): Navigation drawer
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  int get _currentIndex => navigationShell.currentIndex;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width > 840) {
          return _buildDrawer(context);
        } else if (width >= 600) {
          return _buildRail(context);
        } else {
          return _buildBottomNav(context);
        }
      },
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: 'Timeline',
            tooltip: 'View your photos chronologically',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Albums',
            tooltip: 'Browse albums and folders',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Favorites',
            tooltip: 'View your favorite photos',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
            tooltip: 'App settings and preferences',
          ),
        ],
      ),
    );
  }

  Widget _buildRail(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _currentIndex,
            onDestinationSelected: _onTap,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.photo_library, size: 32),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.timeline_outlined),
                selectedIcon: Icon(Icons.timeline),
                label: Text('Timeline'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: Text('Albums'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.favorite_outline),
                selectedIcon: Icon(Icons.favorite),
                label: Text('Favorites'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationDrawer(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              _onTap(index);
              Navigator.of(context).pop();
            },
            children: const [
              Padding(
                padding: EdgeInsets.fromLTRB(28, 16, 28, 24),
                child: Text(
                  'LumoVault',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.timeline_outlined),
                selectedIcon: Icon(Icons.timeline),
                label: Text('Timeline'),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: Text('Albums'),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.favorite_outline),
                selectedIcon: Icon(Icons.favorite),
                label: Text('Favorites'),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
