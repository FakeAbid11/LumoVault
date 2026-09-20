import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Top-right gear on the main tabs' app bars (Google Photos style).
///
/// Settings is no longer a bottom-nav tab, so every content tab surfaces it
/// here instead. Pushes (rather than `go`) so the tab underneath stays
/// mounted and the back arrow returns the user to where they were.
class SettingsGearButton extends StatelessWidget {
  const SettingsGearButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Symbols.settings),
      tooltip: 'Settings',
      onPressed: () => context.push('/settings'),
    );
  }
}
