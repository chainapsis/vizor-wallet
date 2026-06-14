/// Typography tokens from the Figma design system.
///
/// The Figma `Fonts` variable collection has a Desktop and a Mobile mode
/// (`3 Fonts-3.zip`). Both modes are materialized as complete const
/// token sets — [AppTypographyDesktop] and [AppTypographyMobile] — and
/// [AppTypography] selects between them at **compile time** via
/// [kAppFormFactor], so call sites keep the familiar
/// `AppTypography.bodyMedium` shape, stay const, and the unused set is
/// tree-shaken out of release builds. Reference a mode set directly only
/// in tooling (widgetbook galleries, token tests) that must show both
/// modes inside one binary.
///
/// Naming maps Figma → Dart by full word and camelCase where possible:
/// `Headline L` → `headlineLarge`, `Body L` → `bodyLarge`,
/// `Label S` → `labelSmall`, `Code M` → `codeMedium`. The one outlier is
/// `Body M Medium`, the emphasis variant of the regular body — surfaced
/// as [AppTypography.bodyMediumStrong]. The old `display*` constants are
/// legacy aliases onto the headline scale (`displayLarge` /
/// `displayMedium` → `Headline XL`, `displaySmall` → `Headline L`).
///
/// Font sizes and letter spacings are authored in logical pixels. The
/// sans families and letter spacings are identical across modes; the
/// headline scale keeps Libre Caslon Text in both modes, with mobile-only
/// size adjustments for `Headline XL` and `Headline M`. Line heights are
/// stored as the unitless multiplier Flutter expects (`TextStyle.height`)
/// — computed as `figmaLineHeightPx / fontSizePx` so the original Figma
/// design still reproduces exactly.
///
/// Colors are not baked into these styles. Callers merge colors in at
/// the call site (usually through `DefaultTextStyle.merge` or
/// `style.copyWith(color: context.colors.text.primary)`). This keeps
/// the token a pure typographic concern and lets it work with whichever
/// semantic text color the caller needs.
library;

import 'package:flutter/widgets.dart';

import '../layout/app_form_factor.dart';

// ─── Mode-invariant styles (identical in both Figma modes) ───────────

/// Figma `Headline L` — Libre Caslon Text Regular, 32 / 33 px.
const _headlineL = TextStyle(
  fontFamily: 'Libre Caslon Text',
  fontWeight: FontWeight.w400,
  fontSize: 32,
  height: 33 / 32,
  letterSpacing: 0,
);

/// Figma `Headline M` — Libre Caslon Text Regular, 28 / 30 px, −0.28.
const _headlineM = TextStyle(
  fontFamily: 'Libre Caslon Text',
  fontWeight: FontWeight.w400,
  fontSize: 28,
  height: 30 / 28,
  letterSpacing: -0.28,
);

/// Figma `Headline M`, Mobile mode — Libre Caslon Text, 24 / 28 px, −0.4.
const _headlineMMobile = TextStyle(
  fontFamily: 'Libre Caslon Text',
  fontWeight: FontWeight.w400,
  fontSize: 24,
  height: 28 / 24,
  letterSpacing: -0.4,
);

/// Figma `Code M` — Geist Mono Medium, 14 / 21 px.
const _codeMDesktop = TextStyle(
  fontFamily: 'Geist Mono',
  fontWeight: FontWeight.w500,
  fontSize: 14,
  height: 21 / 14,
  letterSpacing: 0,
);

/// Figma `Code M`, Mobile mode — Geist Mono Medium, 16 / 21 px.
const _codeMMobile = TextStyle(
  fontFamily: 'Geist Mono',
  fontWeight: FontWeight.w500,
  fontSize: 16,
  height: 21 / 16,
  letterSpacing: 0,
);

/// Figma `Code S` — Geist Mono Medium, 13 / 17 px.
const _codeS = TextStyle(
  fontFamily: 'Geist Mono',
  fontWeight: FontWeight.w500,
  fontSize: 13,
  height: 17 / 13,
  letterSpacing: 0,
);

/// The Desktop mode of the Figma `Fonts` collection.
abstract final class AppTypographyDesktop {
  /// Figma `Headline XL` — 45 / 48 px, letter-spacing −1.35.
  static const displayLarge = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 45,
    height: 48 / 45,
    letterSpacing: -1.35,
  );

  static const displayMedium = displayLarge;
  static const displaySmall = _headlineL;
  static const headlineLarge = _headlineL;
  static const headlineMedium = _headlineM;

  /// Figma `Headline S` — Geist Medium, 16 / 20 px.
  static const headlineSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 20 / 16,
    letterSpacing: 0,
  );

  /// Figma `Body L` — Geist Medium, 16 / 24 px, −0.24.
  static const bodyLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 24 / 16,
    letterSpacing: -0.24,
  );

  /// Figma `Body M` — Geist Regular, 14 / 21 px, −0.21.
  static const bodyMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 21 / 14,
    letterSpacing: -0.21,
  );

  /// Figma `Body M Medium` — Geist Medium, 14 / 21 px, −0.21.
  static const bodyMediumStrong = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 21 / 14,
    letterSpacing: -0.21,
  );

  /// Figma `Body S` — Geist Regular, 12 / 18 px, −0.12.
  static const bodySmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 18 / 12,
    letterSpacing: -0.12,
  );

  /// Figma `Body XS` — Geist Regular, 11 / 16 px, −0.055.
  static const bodyExtraSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 11,
    height: 16 / 11,
    letterSpacing: -0.055,
  );

  /// Figma `Label M` — Geist Medium, 14 / 16 px, −0.06.
  static const labelLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 16 / 14,
    letterSpacing: -0.06,
  );

  /// Figma `Label S` — Geist Medium, 13 / 14 px.
  static const labelMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 14 / 13,
    letterSpacing: 0,
  );

  static const labelSmall = labelMedium;
  static const codeMedium = _codeMDesktop;
  static const codeSmall = _codeS;
}

/// The Mobile mode of the Figma `Fonts` collection.
///
/// Families, weights, and letter spacings match the desktop set except
/// where the Figma mobile mode explicitly changes metrics (`Headline XL`,
/// `Headline M`, body/label scale, and `Code M`).
abstract final class AppTypographyMobile {
  /// Figma `Headline XL` — Libre Caslon Text, 40 / 40 px, −1.35.
  static const displayLarge = TextStyle(
    fontFamily: 'Libre Caslon Text',
    fontWeight: FontWeight.w400,
    fontSize: 40,
    height: 40 / 40,
    letterSpacing: -1.35,
  );

  static const displayMedium = displayLarge;
  static const displaySmall = _headlineL;
  static const headlineLarge = _headlineL;
  static const headlineMedium = _headlineMMobile;

  /// Figma `Headline S` — Geist Medium, 18 / 22 px.
  static const headlineSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 18,
    height: 22 / 18,
    letterSpacing: 0,
  );

  /// Figma `Body L` — Geist Medium, 18 / 26 px, −0.24.
  static const bodyLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 18,
    height: 26 / 18,
    letterSpacing: -0.24,
  );

  /// Figma `Body M` — Geist Regular, 16 / 25 px, −0.21.
  static const bodyMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 25 / 16,
    letterSpacing: -0.21,
  );

  /// Figma `Body M Medium` — Geist Medium, 16 / 25 px, −0.21.
  static const bodyMediumStrong = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 25 / 16,
    letterSpacing: -0.21,
  );

  /// Figma `Body S` — Geist Regular, 14 / 20 px, −0.12.
  static const bodySmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: -0.12,
  );

  /// Figma `Body XS` — Geist Regular, 13 / 18 px, −0.055.
  static const bodyExtraSmall = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 18 / 13,
    letterSpacing: -0.055,
  );

  /// Figma `Label M` — Geist Medium, 16 / 17 px, −0.06.
  static const labelLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 16,
    height: 17 / 16,
    letterSpacing: -0.06,
  );

  /// Figma `Label S` — Geist Medium, 14 / 15 px.
  static const labelMedium = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 15 / 14,
    letterSpacing: 0,
  );

  static const labelSmall = labelMedium;
  static const codeMedium = _codeMMobile;
  static const codeSmall = _codeS;
}

const _mobile = kAppFormFactor == AppFormFactor.mobile;

/// The typography tokens for the form factor this binary was built for.
///
/// See the library doc above for the selection mechanism and
/// [AppTypographyDesktop] / [AppTypographyMobile] for per-style Figma
/// metrics.
abstract final class AppTypography {
  // ─── Display (legacy aliases onto the headline scale) ─────────────

  /// Largest onboarding/welcome headline (Figma `Headline XL`).
  static const displayLarge = _mobile
      ? AppTypographyMobile.displayLarge
      : AppTypographyDesktop.displayLarge;

  /// Hero headlines (Figma `Headline XL`).
  static const displayMedium = displayLarge;

  /// Step-level headlines inside onboarding flows (Figma `Headline L`).
  static const displaySmall = _mobile
      ? AppTypographyMobile.displaySmall
      : AppTypographyDesktop.displaySmall;

  // ─── Headline ─────────────────────────────────────────────────────

  /// Section headings inside content panes (Figma `Headline L`).
  static const headlineLarge = _mobile
      ? AppTypographyMobile.headlineLarge
      : AppTypographyDesktop.headlineLarge;

  /// Sub-section headings (Figma `Headline M`).
  static const headlineMedium = _mobile
      ? AppTypographyMobile.headlineMedium
      : AppTypographyDesktop.headlineMedium;

  /// Card titles, group labels (Figma `Headline S`).
  static const headlineSmall = _mobile
      ? AppTypographyMobile.headlineSmall
      : AppTypographyDesktop.headlineSmall;

  // ─── Body ─────────────────────────────────────────────────────────

  /// Comfortable paragraph copy, intro descriptions (Figma `Body L`).
  static const bodyLarge = _mobile
      ? AppTypographyMobile.bodyLarge
      : AppTypographyDesktop.bodyLarge;

  /// Default paragraph and subtitle copy (Figma `Body M`).
  static const bodyMedium = _mobile
      ? AppTypographyMobile.bodyMedium
      : AppTypographyDesktop.bodyMedium;

  /// Emphasis variant of [bodyMedium]; same metrics, medium weight. Use
  /// for inline emphasis where italic / bold would over-shout (Figma
  /// `Body M Medium`).
  static const bodyMediumStrong = _mobile
      ? AppTypographyMobile.bodyMediumStrong
      : AppTypographyDesktop.bodyMediumStrong;

  /// Fine print, legal footers, metadata (Figma `Body S`).
  static const bodySmall = _mobile
      ? AppTypographyMobile.bodySmall
      : AppTypographyDesktop.bodySmall;

  /// Smallest readable copy: footnotes, dense table cells, chip text
  /// (Figma `Body XS`).
  static const bodyExtraSmall = _mobile
      ? AppTypographyMobile.bodyExtraSmall
      : AppTypographyDesktop.bodyExtraSmall;

  // ─── Label ────────────────────────────────────────────────────────

  /// Button labels and nav item text (Figma `Label M`).
  static const labelLarge = _mobile
      ? AppTypographyMobile.labelLarge
      : AppTypographyDesktop.labelLarge;

  /// Compact label copy (Figma `Label S`).
  static const labelMedium = _mobile
      ? AppTypographyMobile.labelMedium
      : AppTypographyDesktop.labelMedium;

  /// Micro-copy: tag pills, status badges, dense controls (Figma
  /// `Label S`).
  static const labelSmall = labelMedium;

  // ─── Code ─────────────────────────────────────────────────────────
  // Geist Mono — see `pubspec.yaml`. Use for content where character
  // alignment matters: addresses, transaction IDs, mnemonics, hex
  // dumps.

  /// Primary monospace copy (Figma `Code M`).
  static const codeMedium = _mobile
      ? AppTypographyMobile.codeMedium
      : AppTypographyDesktop.codeMedium;

  /// Secondary monospace copy: mnemonic word indices, compact numeric
  /// metadata (Figma `Code S`).
  static const codeSmall = _codeS;
}
