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
/// * [warning] — Inline caution copy. Backed by the current gold utility
///   token for compatibility with existing warning call sites.
/// * [destructive] — Destructive utility copy.
/// * [success] — Positive / success utility copy.
/// * [brandCrimson] — Brand-colored inline text accent.
/// * [homeCard] — Exception text used on the home balance card. Theme-invariant.
class AppTextColors {
  const AppTextColors({
    required this.accent,
    required this.primary,
    required this.secondary,
    required this.muted,
    required this.disabled,
    required this.inverse,
    required this.warning,
    required this.destructive,
    required this.success,
    required this.brandCrimson,
    required this.homeCard,
  });

  final Color accent;
  final Color primary;
  final Color secondary;
  final Color muted;
  final Color disabled;
  final Color inverse;
  final Color warning;
  final Color destructive;
  final Color success;
  final Color brandCrimson;
  final Color homeCard;

  static const dark = AppTextColors(
    accent: Primitives.p900Dark,
    primary: Primitives.p700Dark,
    secondary: Primitives.p600Dark,
    muted: Primitives.p500Dark,
    disabled: Primitives.p400Dark,
    inverse: Primitives.p0Dark,
    warning: GoldPrimitives.p500Dark,
    destructive: PlumPrimitives.p500Dark,
    success: GoldPrimitives.p500Dark,
    brandCrimson: CrimsonPrimitives.p400Dark,
    homeCard: Primitives.p800Dark,
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
    warning: GoldPrimitives.p400Light,
    destructive: PlumPrimitives.p300Light,
    success: GoldPrimitives.p400Light,
    brandCrimson: CrimsonPrimitives.p400Light,
    homeCard: Primitives.p800Dark,
  );
}
