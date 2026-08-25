import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/extensions/context_extensions.dart';

void main() {
  group('BuildContextExtensions', () {
    testWidgets('theme returns ThemeData', (tester) async {
      late ThemeData capturedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedTheme = context.theme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTheme, isA<ThemeData>());
    });

    testWidgets('colorScheme returns ColorScheme', (tester) async {
      late ColorScheme capturedColorScheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedColorScheme = context.colorScheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedColorScheme, isA<ColorScheme>());
    });

    testWidgets('textTheme returns TextTheme', (tester) async {
      late TextTheme capturedTextTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedTextTheme = context.textTheme;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(capturedTextTheme, isA<TextTheme>());
    });

    testWidgets('isDarkMode returns false in light theme', (tester) async {
      late bool isDark;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Builder(
            builder: (context) {
              isDark = context.isDarkMode;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDark, isFalse);
    });

    testWidgets('isDarkMode returns true in dark theme', (tester) async {
      late bool isDark;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) {
              isDark = context.isDarkMode;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDark, isTrue);
    });

    testWidgets('screenSize returns Size', (tester) async {
      late Size screenSize;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              screenSize = context.screenSize;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(screenSize, isA<Size>());
      expect(screenSize.width, greaterThan(0));
      expect(screenSize.height, greaterThan(0));
    });
  });
}
