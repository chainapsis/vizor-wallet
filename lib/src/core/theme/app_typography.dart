import 'package:flutter/widgets.dart';

/// Typography tokens from the Figma design system.
///
/// Mirrors the `Desktop / {Display, Body, Label, Code}` group of the
/// Figma token sheet (`Mode 1.tokens.json`) one-to-one — every named
/// style there has a matching constant here, and changes to the sheet
/// land in this file.
///
/// Naming maps Figma → Dart by full word and camelCase: `Display Medium`
/// → `displayMedium`, `Body L` → `bodyLarge`, `Label S` → `labelSmall`,
/// `Code M` → `codeMedium`. The one outlier is `Body M Medium`, the
/// emphasis variant of the regular body — surfaced as
/// [bodyMediumStrong].
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

  /// Display Large — largest onboarding/welcome headline.
  ///
  /// Libre Caslon Text Regular, 60 / 62.4 px, letter-spacing −2.
  static const displayLarge = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 60,
    height: 62.4 / 60,
    letterSpacing: -2,
  );

  /// Display Medium — hero headlines (e.g. "Welcome to Vizor").
  ///
  /// Libre Caslon Text Regular, 45 / 52 px, letter-spacing −1.35.
  static const displayMedium = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 45,
    height: 52 / 45,
    letterSpacing: -1.35,
  );

  /// Display Small — step-level headlines inside onboarding flows
  /// (e.g. "Welcome to the Shielded World").
  ///
  /// Libre Caslon Text Regular, 36 / 44 px, letter-spacing −0.72.
  static const displaySmall = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 36,
    height: 44 / 36,
    letterSpacing: -0.72,
  );

  /// Headline Large — section headings inside content panes.
  ///
  /// Libre Caslon Text Regular, 32 / 40 px, letter-spacing 0.
  static const headlineLarge = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 32,
    height: 40 / 32,
    letterSpacing: 0,
  );

  /// Headline Medium — sub-section headings.
  ///
  /// Libre Caslon Text Regular, 28 / 36 px, letter-spacing −0.28.
  static const headlineMedium = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 28,
    height: 36 / 28,
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

  /// Label L — button labels at the compact (Small) button size; nav
  /// item text in side panels.
  ///
  /// Geist Medium, 14 / 18 px, letter-spacing −0.14.
  static const labelLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 18 / 14,
    letterSpacing: -0.14,
  );

  /// Label M — button labels and inline UI copy at the same size.
  ///
  /// Geist Medium, 12 / 16 px, letter-spacing −0.06.
  static const labelMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: -0.06,
  );

  /// Label S — micro-copy: tag pills, status badges, dense controls.
  ///
  /// Geist Medium, 11 / 14 px, letter-spacing 0.
  static const labelSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 11,
    height: 14 / 11,
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
  /// Geist Mono Medium, 12 / 17 px, letter-spacing 0.
  static const codeSmall = TextStyle(
    fontFamily: 'Geist Mono',
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 17 / 12,
    letterSpacing: 0,
  );
}
