/// Spacing scale from the Figma token export (Mode 1 / Spacing).
///
/// All values are in logical pixels (what Flutter sees). The underlying
/// Figma tokens are named `{N}dp` with an implicit 2× multiplier, so this
/// file deliberately stores the expanded numeric value — `AppSpacing.sm` is
/// 16, matching the Figma fallback `var(--spacing/sm, 16px)`.
///
/// Kept as static constants for now — the values are mode-invariant so they
/// don't need to live inside `AppThemeData`. If the design ever introduces
/// density variants (comfortable vs compact), promote this into the theme.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double sm = 16;
  static const double md = 24;
  // "base" sits at step 6, not in the middle of the scale. Matches Figma.
  static const double base = 32;
  static const double lg = 48;
  static const double xl = 64;
  // Figma names these `2xl` / `3xl`; Dart identifiers can't start with a
  // digit, so we spell the multiplier after the prefix.
  static const double xl2 = 96;
  static const double xl3 = 128;
}
