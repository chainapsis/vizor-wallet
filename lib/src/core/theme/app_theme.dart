import 'package:flutter/material.dart';

/// Zcash Wallet design system — Stitch-based tokens.
///
/// Usage: `Theme.of(context).colorScheme.primary`
///        `Theme.of(context).textTheme.displayLarge`
///
/// All screens must use Theme.of(context) — never hardcode Color() values.
/// This enables reactive light/dark mode switching.

// ---------------------------------------------------------------------------
// Light palette (Stitch)
// ---------------------------------------------------------------------------

const _lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  // Surfaces
  surface: Color(0xFFF9F9F9),
  onSurface: Color(0xFF2D3435),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF2F4F4),
  surfaceContainer: Color(0xFFEBEEEF),
  surfaceContainerHigh: Color(0xFFE4E9EA),
  surfaceContainerHighest: Color(0xFFDDE4E5),
  onSurfaceVariant: Color(0xFF5A6061),
  // Primary
  primary: Color(0xFF5F5E5E),
  onPrimary: Color(0xFFFAF7F6),
  primaryContainer: Color(0xFFE5E2E1),
  onPrimaryContainer: Color(0xFF525151),
  // Secondary
  secondary: Color(0xFF4D626C),
  onSecondary: Color(0xFFF2FAFF),
  secondaryContainer: Color(0xFFCFE6F2),
  onSecondaryContainer: Color(0xFF40555F),
  // Tertiary — green = shielded/private
  tertiary: Color(0xFF1C6D25),
  onTertiary: Color(0xFFEAFFE2),
  tertiaryContainer: Color(0xFF9DF197),
  onTertiaryContainer: Color(0xFF005C15),
  // Error
  error: Color(0xFF9F403D),
  onError: Color(0xFFFFF7F6),
  errorContainer: Color(0xFFFE8983),
  onErrorContainer: Color(0xFF752121),
  // Outline
  outline: Color(0xFF757C7D),
  outlineVariant: Color(0xFFADB3B4),
  // Misc
  inverseSurface: Color(0xFF0C0F0F),
  onInverseSurface: Color(0xFF9C9D9D),
  inversePrimary: Color(0xFFFFFFFF),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

// ---------------------------------------------------------------------------
// Dark palette — tinted darks, no pure black
// ---------------------------------------------------------------------------

const _darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  // Surfaces — cool blue-grey undertone
  surface: Color(0xFF141818),
  onSurface: Color(0xFFE2E3E3),
  surfaceContainerLowest: Color(0xFF0E1111),
  surfaceContainerLow: Color(0xFF1A1E1E),
  surfaceContainer: Color(0xFF1F2424),
  surfaceContainerHigh: Color(0xFF282D2D),
  surfaceContainerHighest: Color(0xFF333838),
  onSurfaceVariant: Color(0xFFA0A6A7),
  // Primary
  primary: Color(0xFFD6D4D3),
  onPrimary: Color(0xFF2A2A2A),
  primaryContainer: Color(0xFF484747),
  onPrimaryContainer: Color(0xFFE5E2E1),
  // Secondary
  secondary: Color(0xFFC1D8E4),
  onSecondary: Color(0xFF1A2F39),
  secondaryContainer: Color(0xFF3A4F59),
  onSecondaryContainer: Color(0xFFCFE6F2),
  // Tertiary — green stays recognizable
  tertiary: Color(0xFF90E28A),
  onTertiary: Color(0xFF00390C),
  tertiaryContainer: Color(0xFF12661E),
  onTertiaryContainer: Color(0xFF9DF197),
  // Error
  error: Color(0xFFFE8983),
  onError: Color(0xFF4E0309),
  errorContainer: Color(0xFF752121),
  onErrorContainer: Color(0xFFFE8983),
  // Outline
  outline: Color(0xFF6B7273),
  outlineVariant: Color(0xFF3E4445),
  // Misc
  inverseSurface: Color(0xFFE2E3E3),
  onInverseSurface: Color(0xFF2D3435),
  inversePrimary: Color(0xFF5F5E5E),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

// ---------------------------------------------------------------------------
// Text themes
// ---------------------------------------------------------------------------

const _headlineFamily = 'Manrope';
const _bodyFamily = 'Inter';

TextTheme _buildTextTheme(Brightness brightness) {
  final color = brightness == Brightness.light
      ? const Color(0xFF2D3435)
      : const Color(0xFFE2E3E3);

  return TextTheme(
    // Hero balance (56px Manrope 800)
    displayLarge: TextStyle(
      fontFamily: _headlineFamily,
      fontWeight: FontWeight.w800,
      fontSize: 56,
      height: 1.0,
      letterSpacing: -2,
      color: color,
    ),
    // Large heading (28px Manrope 600) — e.g. "ZEC" unit
    displayMedium: TextStyle(
      fontFamily: _headlineFamily,
      fontWeight: FontWeight.w600,
      fontSize: 28,
      height: 1.2,
      letterSpacing: -0.5,
      color: color,
    ),
    // Section heading (20px Manrope 700)
    titleLarge: TextStyle(
      fontFamily: _headlineFamily,
      fontWeight: FontWeight.w700,
      fontSize: 20,
      height: 1.2,
      letterSpacing: -0.3,
      color: color,
    ),
    // List item title (15px Manrope 700)
    titleMedium: TextStyle(
      fontFamily: _headlineFamily,
      fontWeight: FontWeight.w700,
      fontSize: 15,
      height: 1.4,
      color: color,
    ),
    // Body (14px Inter 400)
    bodyLarge: TextStyle(
      fontFamily: _bodyFamily,
      fontWeight: FontWeight.w400,
      fontSize: 14,
      height: 1.5,
      color: color,
    ),
    // Body secondary (14px Inter 500)
    bodyMedium: TextStyle(
      fontFamily: _bodyFamily,
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 1.5,
      color: color,
    ),
    // Small body (12px Inter 500)
    bodySmall: TextStyle(
      fontFamily: _bodyFamily,
      fontWeight: FontWeight.w500,
      fontSize: 12,
      height: 1.5,
      color: color,
    ),
    // Uppercase label (11px Inter 600)
    labelLarge: TextStyle(
      fontFamily: _bodyFamily,
      fontWeight: FontWeight.w600,
      fontSize: 11,
      letterSpacing: 1.5,
      color: color,
    ),
    // Button label (11px Manrope 700)
    labelMedium: TextStyle(
      fontFamily: _headlineFamily,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: 2,
      color: color,
    ),
    // Caption (10px Inter 700)
    labelSmall: TextStyle(
      fontFamily: _bodyFamily,
      fontWeight: FontWeight.w700,
      fontSize: 10,
      letterSpacing: 1.5,
      color: color,
    ),
  );
}

// ---------------------------------------------------------------------------
// ThemeData builders
// ---------------------------------------------------------------------------

ThemeData buildLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: _lightColorScheme,
    textTheme: _buildTextTheme(Brightness.light),
    fontFamily: _bodyFamily,
    scaffoldBackgroundColor: _lightColorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: _lightColorScheme.surface,
      foregroundColor: _lightColorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: _headlineFamily,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: -0.3,
        color: _lightColorScheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _lightColorScheme.primary,
        foregroundColor: _lightColorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: _headlineFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _lightColorScheme.onSurface,
        side: BorderSide(color: _lightColorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: _headlineFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _darkColorScheme,
    textTheme: _buildTextTheme(Brightness.dark),
    fontFamily: _bodyFamily,
    scaffoldBackgroundColor: _darkColorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: _darkColorScheme.surface,
      foregroundColor: _darkColorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: _headlineFamily,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: -0.3,
        color: _darkColorScheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _darkColorScheme.primary,
        foregroundColor: _darkColorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: _headlineFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _darkColorScheme.onSurface,
        side: BorderSide(color: _darkColorScheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: _headlineFamily,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    ),
  );
}
