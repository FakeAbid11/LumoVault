import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shows a snackbar that clears the shell's floating navigation capsule.
///
/// The app shell draws its bottom navigation as a floating capsule with
/// `Scaffold.extendBody: true`, so on the four main tabs there is no inner
/// `bottomNavigationBar` to lift a floating snackbar above it — snackbars
/// shown there would render inside the capsule's zone (which reaches ~96px
/// above the bottom edge: 40px SafeArea minimum + 56px NavigationBar).
///
/// On phone-width surfaces this helper anchors the snackbar above the
/// capsule; everywhere else (pushed routes, tablets with rail/drawer) it
/// behaves like a normal floating snackbar.
void showLumoSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
}) {
  final double bottomInset = MediaQuery.paddingOf(context).bottom;
  final bool hasCapsule = MediaQuery.sizeOf(context).width < 600;
  final double bottomMargin = hasCapsule
      ? math.max(bottomInset + 16, 104)
      : bottomInset + 16;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: action,
      // Explicit so the margin is honored even if the theme's floating
      // behavior ever changes.
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomMargin),
    ),
  );
}
