import 'package:flutter/widgets.dart';

/// Typography tokens from the Figma design system.
///
/// Mirrors the desktop Figma token sheet (`Desktop.tokens.json`). Public
/// names are kept stable for existing call sites, so the old `display*`
/// constants are aliases onto the current headline scale.
///
/// Serif styles use Young Serif Medium with the OpenType 'case' feature
/// enabled: Young Serif defaults to old-style figures whose descenders sit
/// below the baseline, and 'case' swaps them for uniform lining digits.
/// (The original `Desktop.tokens.json` export predated the design system's
/// serif migration and still said Libre Caslon; the live Figma file uses
/// Young Serif exclusively.)
///
/// Naming maps Figma → Dart by full word and camelCase where possible:
/// `Headline L` → `headlineLarge`, `Body L` → `bodyLarge`,
/// `Label S` → `labelSmall`, `Code M` → `codeMedium`. The one outlier is
/// `Body M Medium`, the emphasis variant of the regular body — surfaced
/// as [bodyMediumStrong].
///
/// Font sizes and letter spacings are authored in logical pixels. Line
/// heights are stored as the unitless multiplier Flutter expects
/// (`TextStyle.height`) — computed as `figmaLineHeightPx / fontSizePx`
/// so the original Figma design still reproduces exactly.
///
/// Colors are not baked into these styles. Callers merge colors in at
/// the call site (usually through `DefaultTextStyle.merge` or
/// `style.copyWith(color: context.colors.text.primary)`). This keeps
/// the token a pure typographic concern and lets it work with whichever
/// semantic text color the caller needs.
///
/// Kept as a static-const namespace rather than a field on
/// [AppThemeData] for the same reason as `AppSpacing` — text sizes are
/// mode-invariant. Migrate into the theme only if a density / platform
/// variant ever needs to switch them.
abstract final class AppTypography {
  // ─── Display ──────────────────────────────────────────────────────

  /// Legacy display alias for Headline XL — largest onboarding/welcome
  /// headline.
  ///
  /// Young Serif Medium, 45 / 48 px, letter-spacing −1.35.
  static const displayLarge = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.enable('case')],
    fontSize: 45,
    height: 48 / 45,
    letterSpacing: -1.35,
  );

  /// Legacy display alias for Headline XL — hero headlines.
  ///
  /// Young Serif Medium, 45 / 48 px, letter-spacing −1.35.
  static const displayMedium = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.enable('case')],
    fontSize: 45,
    height: 48 / 45,
    letterSpacing: -1.35,
  );

  /// Legacy display alias for Headline L — step-level headlines inside
  /// onboarding flows.
  ///
  /// Young Serif Medium, 32 / 33 px, letter-spacing 0.
  static const displaySmall = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.enable('case')],
    fontSize: 32,
    height: 33 / 32,
    letterSpacing: 0,
  );

  /// Headline Large — section headings inside content panes.
  ///
  /// Young Serif Medium, 32 / 33 px, letter-spacing 0.
  static const headlineLarge = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.enable('case')],
    fontSize: 32,
    height: 33 / 32,
    letterSpacing: 0,
  );

  /// Headline Medium — sub-section headings.
  ///
  /// Young Serif Medium, 28 / 30 px, letter-spacing −0.28.
  static const headlineMedium = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.enable('case')],
    fontSize: 28,
    height: 30 / 28,
    letterSpacing: -0.28,
  );

  /// Headline Small — card titles, group labels.
  ///
  /// Geist Medium, 16 / 20 px, letter-spacing 0.
  static const headlineSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 20 / 16,
    letterSpacing: 0,
  );

  // ─── Body ─────────────────────────────────────────────────────────

  /// Body L — comfortable paragraph copy, intro descriptions.
  ///
  /// Geist Medium, 16 / 24 px, letter-spacing −0.24.
  static const bodyLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: -0.24,
  );

  /// Body M — default paragraph and subtitle copy.
  ///
  /// Geist Regular, 14 / 21 px, letter-spacing −0.21.
  static const bodyMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 21 / 14,
    letterSpacing: -0.21,
  );

  /// Body M Medium — emphasis variant of [bodyMedium]; same metrics,
  /// medium weight. Use for inline emphasis where italic / bold would
  /// over-shout.
  ///
  /// Geist Medium, 14 / 21 px, letter-spacing −0.21.
  static const bodyMediumStrong = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 21 / 14,
    letterSpacing: -0.21,
  );

  /// Body S — fine print, legal footers, metadata.
  ///
  /// Geist Regular, 12 / 18 px, letter-spacing −0.12.
  static const bodySmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 18 / 12,
    letterSpacing: -0.12,
  );

  /// Body XS — smallest readable copy: footnotes, dense table cells,
  /// chip text.
  ///
  /// Geist Regular, 11 / 16 px, letter-spacing −0.055.
  static const bodyExtraSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 11,
    height: 16 / 11,
    letterSpacing: -0.055,
  );

  // ─── Label ────────────────────────────────────────────────────────

  /// Label M — button labels and nav item text.
  ///
  /// Geist Medium, 14 / 16 px, letter-spacing −0.06.
  static const labelLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 16 / 14,
    letterSpacing: -0.06,
  );

  /// Label S — compact label copy.
  ///
  /// Geist Medium, 13 / 14 px, letter-spacing 0.
  static const labelMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 14 / 13,
    letterSpacing: 0,
  );

  /// Label S — micro-copy: tag pills, status badges, dense controls.
  ///
  /// Geist Medium, 13 / 14 px, letter-spacing 0.
  static const labelSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 14 / 13,
    letterSpacing: 0,
  );

  // ─── Code ─────────────────────────────────────────────────────────
  // Geist Mono — see `pubspec.yaml`. Use for content where character
  // alignment matters: addresses, transaction IDs, mnemonics, hex
  // dumps.

  /// Code M — primary monospace copy (e.g. mnemonic word indices).
  ///
  /// Geist Mono Medium, 14 / 21 px, letter-spacing 0.
  static const codeMedium = TextStyle(
    fontFamily: 'Geist Mono',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 21 / 14,
    letterSpacing: 0,
  );

  /// Code S — secondary monospace copy (e.g. mnemonic word indices,
  /// compact numeric metadata).
  ///
  /// Geist Mono Medium, 13 / 17 px, letter-spacing 0.
  static const codeSmall = TextStyle(
    fontFamily: 'Geist Mono',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 17 / 13,
    letterSpacing: 0,
  );
}
