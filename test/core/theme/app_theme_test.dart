import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/theme/app_colors.dart';
import 'package:lumovault/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses Material 3', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme uses Material 3', () {
      final theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
    });

    test('light theme has brightness light', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
    });

    test('dark theme has brightness dark', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
    });

    test('both themes derive their primary from the brand seed', () {
      // The launcher icon and the app chrome have to read as one brand, so
      // primary must stay in the seed's hue family in both brightnesses.
      // Material shifts hue slightly while fitting the tonal palette; 20
      // degrees is wide enough for that and far narrower than the ~60 that
      // would let primary drift into a neighbouring hue.
      final seedHue = HSLColor.fromColor(AppColors.seed).hue;

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final hue = HSLColor.fromColor(theme.colorScheme.primary).hue;
        expect(
          (hue - seedHue).abs(),
          lessThan(20),
          reason: 'primary ${theme.colorScheme.primary} is off the brand hue',
        );
      }
    });

    test('primary keeps the logo saturation rather than washing out', () {
      // Guards the `vibrant` scheme variant: the default `tonalSpot` produces
      // a dusty grey-purple around 0.25 saturation, which no longer matches
      // the icon's vivid violet.
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(
          HSLColor.fromColor(theme.colorScheme.primary).saturation,
          greaterThan(0.5),
          reason: 'primary ${theme.colorScheme.primary} looks desaturated',
        );
      }
    });

    test('a dynamic scheme overrides the brand seed', () {
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00FF00),
        brightness: Brightness.light,
      );
      final theme = AppTheme.light(dynamicScheme: dynamicScheme);
      expect(theme.colorScheme.primary, dynamicScheme.primary);
    });

    test('scheme roles pair legible foregrounds with their containers', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        final scheme = theme.colorScheme;
        final pairs = {
          'primary': (scheme.primary, scheme.onPrimary),
          'primaryContainer': (
            scheme.primaryContainer,
            scheme.onPrimaryContainer,
          ),
          'surface': (scheme.surface, scheme.onSurface),
        };
        pairs.forEach((role, pair) {
          final (background, foreground) = pair;
          expect(
            (background.computeLuminance() - foreground.computeLuminance())
                .abs(),
            greaterThan(0.3),
            reason: '$role has too little contrast in ${theme.brightness}',
          );
        });
      }
    });

    test('themes have text themes', () {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();
      expect(lightTheme.textTheme, isNotNull);
      expect(darkTheme.textTheme, isNotNull);
    });

    test('themes have app bar theme', () {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();
      expect(lightTheme.appBarTheme, isNotNull);
      expect(darkTheme.appBarTheme, isNotNull);
    });

    test('themes have navigation bar theme', () {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();
      expect(lightTheme.navigationBarTheme, isNotNull);
      expect(darkTheme.navigationBarTheme, isNotNull);
    });

    test('themes have card theme', () {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();
      expect(lightTheme.cardTheme, isNotNull);
      expect(darkTheme.cardTheme, isNotNull);
    });
  });
}
