import 'package:flutter/material.dart';

/// LumoVault's brand palette.
///
/// The brand is an indigo/blue family, chosen for a calm, dependable "secure
/// vault" feel that reads well behind photo thumbnails in dark mode. It
/// intentionally diverges from the current launcher icon (`assets/icon/
/// app_icon.png`, a violet gradient) — the icon is left unchanged; the app
/// chrome no longer tries to match it.
///
/// [seed] is the only value the Material scheme is built from — every surface,
/// container and outline role is derived by `ColorScheme.fromSeed` in
/// `AppTheme`, not hand-listed here, so they can never drift apart. The
/// remaining constants are for the handful of places that need a literal brand
/// colour outside the scheme (see [syncing]).
abstract final class AppColors {
  /// The scheme seed: a saturated indigo.
  ///
  /// A saturated dark tone is what a seed needs to be — Material's generator
  /// can lighten it into readable containers, while preserving the hue across
  /// both brightnesses under `DynamicSchemeVariant.vibrant`.
  static const Color seed = brandIndigo;

  /// The primary brand indigo.
  static const Color brandIndigo = Color(0xFF2B5CE6);

  /// Lighter sky-blue, used for the in-flight transfer accent.
  static const Color brandSky = Color(0xFF4FA8FF);

  /// In-flight transfer accent, for the upload/sync status indicators.
  ///
  /// Not a scheme role: these badges sit on the gallery's dark scrim and the
  /// viewer's black backdrop, where `colorScheme.primary` would be either too
  /// dark (light theme) or indistinguishable from the surrounding chrome. This
  /// sky-blue reads clearly on black in both themes and signals "moving data".
  static const Color syncing = brandSky;
}
