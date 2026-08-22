/// Process-wide flag for whether page transition animations are enabled.
///
/// Mirrors the [AppLogger] global-flag pattern: the router builds its
/// transition pages once and cannot cheaply watch a provider per navigation,
/// so it reads this static instead. [LumoVaultApp] keeps it in sync with
/// `AppSettings.animationsEnabled` on every build.
///
/// When false, custom route transitions collapse to an instant cut (zero
/// duration, no slide), and the theme's [pageTransitionsTheme] is swapped for
/// a no-animation builder.
abstract final class AppMotion {
  /// True (the default) plays transitions; false disables them app-wide.
  static bool enabled = true;
}
