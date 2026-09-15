import 'package:flutter/material.dart';

/// Utility extensions for BuildContext.
extension BuildContextExtensions on BuildContext {
  /// Current theme data.
  ThemeData get theme => Theme.of(this);

  /// Current color scheme.
  ColorScheme get colorScheme => theme.colorScheme;

  /// Current text theme.
  TextTheme get textTheme => theme.textTheme;

  /// Is dark mode active.
  bool get isDarkMode => theme.brightness == Brightness.dark;

  /// Media query data.
  MediaQueryData get mediaQuery => MediaQuery.of(this);

  /// Screen size.
  Size get screenSize => mediaQuery.size;

  /// Padding.
  EdgeInsets get padding => mediaQuery.padding;

  /// Is keyboard visible.
  bool get isKeyboardVisible => mediaQuery.viewInsets.bottom > 0;
}
