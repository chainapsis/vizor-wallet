import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Text color hierarchy.
///
/// * [accent] — Titles, headings; max contrast.
/// * [primary] — Default body text, paragraphs.
/// * [secondary] — Subtitles, timestamps, metadata.
/// * [muted] — Descriptions. Theme-invariant.
/// * [disabled] — Inactive, unavailable labels.
/// * [inverse] — Text placed on inverted surfaces (e.g. dark text on a light
///   chip inside dark mode).
/// * [warning] — Inline warning copy. Theme-invariant brand yellow.
/// * [brandPurple] / [brandCyan] — Brand-colored inline text accents.
class AppTextColors {
  const AppTextColors({
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.disabled,
    required this.inverse,
    required this.warning,
    required this.brandPurple,
    required this.brandCyan,
  });

  final Color accent;
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color disabled;
  final Color inverse;
  final Color warning;
  final Color brandPurple;
  final Color brandCyan;

  static const dark = AppTextColors(
    accent: Primitives.p800Dark,
    primary: Primitives.p700Dark,
    secondary: Primitives.p600Dark,
    muted: Primitives.p500Dark,
    disabled: Primitives.p400Dark,
    inverse: Primitives.p0Dark,
    // Yellow 400 dark = #FF9617; the same warning hue is mirrored on
    // the light face via `p300Light`, so the inline warning reads
    // identically across modes.
    warning: YellowPrimitives.p400Dark,
    brandPurple: PurplePrimitives.p500Dark,
    brandCyan: CyanPrimitives.p600Dark,
  );

  static const light = AppTextColors(
    // Accent in light mode reaches the *opposite* extreme of the ladder
    // (p900Light = near-black) rather than mirroring p800Dark's step.
    accent: Primitives.p900Light,
    primary: Primitives.p700Light,
    secondary: Primitives.p600Light,
    muted: Primitives.p500Light,
    disabled: Primitives.p400Light,
    inverse: Primitives.p0Light,
    warning: YellowPrimitives.p300Light,
    brandPurple: PurplePrimitives.p200Light,
    brandCyan: CyanPrimitives.p300Light,
  );
}
