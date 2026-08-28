import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Responsive shell that adapts navigation layout based on screen size.
///
/// - Phone (< 600px): Bottom floating capsule navigation bar (Google Photos style)
/// - Tablet (600-840px): Navigation rail
/// - Large Tablet (> 840px): Navigation drawer
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  int get _currentIndex => navigationShell.currentIndex;

  void _onTap(int index) {
    HapticFeedback.selectionClick();
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: NavigationBar(
                height: 56,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedIndex: _currentIndex,
                onDestinationSelected: _onTap,
                labelBehavior:
                    NavigationDestinationLabelBehavior.onlyShowSelected,
                indicatorShape: const StadiumBorder(),
                indicatorColor: colorScheme.secondaryContainer,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Symbols.smartphone, size: 22),
                    selectedIcon: Icon(Symbols.smartphone, size: 22),
                    label: 'Local',
                    tooltip: 'All photos on this device',
                  ),
                  NavigationDestination(
                    icon: Icon(Symbols.cloud_done, size: 22),
                    selectedIcon: Icon(Symbols.cloud_done, size: 22),
                    label: 'Timeline',
                    tooltip: 'Photos backed up to Telegram',
                  ),
                  NavigationDestination(
                    icon: Icon(Symbols.map, size: 22),
                    selectedIcon: Icon(Symbols.map, size: 22),
                    label: 'Map',
                    tooltip: 'Photos on a map by location',
                  ),
                  NavigationDestination(
                    icon: Icon(Symbols.people, size: 22),
                    selectedIcon: Icon(Symbols.people, size: 22),
                    label: 'People',
                    tooltip: 'Photos grouped by person',
                  ),
                  NavigationDestination(
                    icon: Icon(Symbols.settings, size: 22),
                    selectedIcon: Icon(Symbols.settings, size: 22),
                    label: 'Settings',
                    tooltip: 'App settings and preferences',
                  ),
                ],
              ),
            ),
          ),
        ),
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
              child: Icon(Symbols.photo_library, size: 32),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Symbols.smartphone),
                selectedIcon: Icon(Symbols.smartphone),
                label: Text('Local'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.cloud_done),
                selectedIcon: Icon(Symbols.cloud_done),
                label: Text('Timeline'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.map),
                selectedIcon: Icon(Symbols.map),
                label: Text('Map'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.people),
                selectedIcon: Icon(Symbols.people),
                label: Text('People'),
              ),
              NavigationRailDestination(
                icon: Icon(Symbols.settings),
                selectedIcon: Icon(Symbols.settings),
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
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                child: Text(
                  'LumoVault',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Symbols.smartphone),
                selectedIcon: Icon(Symbols.smartphone),
                label: Text('Local'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Symbols.cloud_done),
                selectedIcon: Icon(Symbols.cloud_done),
                label: Text('Timeline'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Symbols.map),
                selectedIcon: Icon(Symbols.map),
                label: Text('Map'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Symbols.people),
                selectedIcon: Icon(Symbols.people),
                label: Text('People'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Symbols.settings),
                selectedIcon: Icon(Symbols.settings),
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
