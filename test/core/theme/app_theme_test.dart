import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses Material 3', () {
      final theme = AppTheme.light;
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme uses Material 3', () {
      final theme = AppTheme.dark;
      expect(theme.useMaterial3, isTrue);
    });

    test('light theme has brightness light', () {
      final theme = AppTheme.light;
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme has brightness dark', () {
      final theme = AppTheme.dark;
      expect(theme.brightness, Brightness.dark);
    });

    test('light theme has valid color scheme', () {
      final theme = AppTheme.light;
      final colorScheme = theme.colorScheme;
      expect(colorScheme.primary, isNotNull);
      expect(colorScheme.onPrimary, isNotNull);
      expect(colorScheme.surface, isNotNull);
      expect(colorScheme.onSurface, isNotNull);
    });

    test('dark theme has valid color scheme', () {
      final theme = AppTheme.dark;
      final colorScheme = theme.colorScheme;
      expect(colorScheme.primary, isNotNull);
      expect(colorScheme.onPrimary, isNotNull);
      expect(colorScheme.surface, isNotNull);
      expect(colorScheme.onSurface, isNotNull);
    });

    test('themes have text themes', () {
      final lightTheme = AppTheme.light;
      final darkTheme = AppTheme.dark;
      expect(lightTheme.textTheme, isNotNull);
      expect(darkTheme.textTheme, isNotNull);
    });

    test('themes have app bar theme', () {
      final lightTheme = AppTheme.light;
      final darkTheme = AppTheme.dark;
      expect(lightTheme.appBarTheme, isNotNull);
      expect(darkTheme.appBarTheme, isNotNull);
    });

    test('themes have navigation bar theme', () {
      final lightTheme = AppTheme.light;
      final darkTheme = AppTheme.dark;
      expect(lightTheme.navigationBarTheme, isNotNull);
      expect(darkTheme.navigationBarTheme, isNotNull);
    });

    test('themes have card theme', () {
      final lightTheme = AppTheme.light;
      final darkTheme = AppTheme.dark;
      expect(lightTheme.cardTheme, isNotNull);
      expect(darkTheme.cardTheme, isNotNull);
    });
  });
}
