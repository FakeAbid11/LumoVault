import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme mode provider.
///
/// Manages light/dark/system theme preference.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
