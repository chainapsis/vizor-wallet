import 'package:flutter/widgets.dart';

/// Typography tokens from the Figma design system.
///
/// Only the styles that are in use today are declared here. The named
/// scales align with the Figma export ("Desktop/Display/Display Medium",
/// "Desktop/Body/Body M" etc.) but shortened to Dart-idiomatic names.
///
/// Font sizes and letter spacings are authored in logical pixels. Line
/// heights are stored as the unitless multiplier Flutter expects
/// (`TextStyle.height`) — computed as `figmaLineHeightPx / fontSizePx`
/// so the original Figma design still reproduces exactly.
///
/// Colors are not baked into these styles. Callers merge colors in at
/// the call site (usually through `DefaultTextStyle.merge` or
/// `style.copyWith(color: context.colors.text.primary)`). This keeps the
/// token a pure typographic concern and lets it work with whichever
/// semantic text color the caller needs.
///
/// Kept as a static-const namespace rather than a field on
/// [AppThemeData] for the same reason as [AppSpacing] — text sizes are
/// mode-invariant. Migrate into the theme only if a density / platform
/// variant ever needs to switch them.
abstract final class AppTypography {
  /// Display Medium — hero headlines (e.g. "Welcome to Zeplr").
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

  /// Label L — button labels at the compact (Small) button size.
  ///
  /// Geist Medium, 14 / 18 px, letter-spacing −0.14.
  static const labelLarge = TextStyle(
    fontFamily: 'Geist',
    fontWeight: FontWeight.w500,
    fontSize: 14,
    height: 18 / 14,
    letterSpacing: -0.14,
  );
}
