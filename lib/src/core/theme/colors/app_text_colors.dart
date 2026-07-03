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
/// * [positiveStrong] — Positive-state copy backed by the green utility ramp.
/// * [destructive] — Destructive utility copy.
/// * [destructiveLight] — Softer destructive copy for secondary error text.
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
    required this.positiveStrong,
    required this.destructive,
    required this.destructiveLight,
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
  final Color positiveStrong;
  final Color destructive;
  final Color destructiveLight;
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
    positiveStrong: GreenPrimitives.p400Dark,
    destructive: PlumPrimitives.p500Dark,
    destructiveLight: PlumPrimitives.p400Dark,
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
    positiveStrong: GreenPrimitives.p500Light,
    destructive: PlumPrimitives.p300Light,
    destructiveLight: PlumPrimitives.p150Light,
    success: GoldPrimitives.p400Light,
    brandCrimson: CrimsonPrimitives.p300Light,
    homeCard: Primitives.p0Light,
  );
}
