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
            icon: Icon(Icons.smartphone_outlined),
            selectedIcon: Icon(Icons.smartphone),
            label: 'Local',
            tooltip: 'All photos on this device',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_done_outlined),
            selectedIcon: Icon(Icons.cloud_done),
            label: 'Timeline',
            tooltip: 'Photos backed up to Telegram',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'People',
            tooltip: 'Photos grouped by detected faces',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
            tooltip: 'Photos on a map by location',
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
                icon: Icon(Icons.smartphone_outlined),
                selectedIcon: Icon(Icons.smartphone),
                label: Text('Local'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_done_outlined),
                selectedIcon: Icon(Icons.cloud_done),
                label: Text('Timeline'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('People'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: Text('Map'),
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
                icon: Icon(Icons.smartphone_outlined),
                selectedIcon: Icon(Icons.smartphone),
                label: Text('Local'),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.cloud_done_outlined),
                selectedIcon: Icon(Icons.cloud_done),
                label: Text('Timeline'),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: Text('People'),
              ),
              NavigationDrawerDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: Text('Map'),
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
