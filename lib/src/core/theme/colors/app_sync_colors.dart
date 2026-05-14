import 'package:flutter/painting.dart';

/// Sync-specific sidebar colors from the semantic sync Figma tokens.
class AppSyncColors {
  const AppSyncColors({
    required this.text,
    required this.textSyncing,
    required this.textError,
    required this.lightSuccess,
    required this.lightError,
  });

  final Color text;
  final Color textSyncing;
  final Color textError;
  final Color lightSuccess;
  final Color lightError;

  static const _darkSuccess = Color(0xFFD3FFE4);
  static const _successIndicator = Color(0xFF0DC87D);
  static const _darkErrorIndicator = Color(0xFFA3A4A4);
  static const _lightErrorIndicator = Color(0xFF858686);

  static const dark = AppSyncColors(
    text: _darkSuccess,
    textSyncing: Color(0xA6D3FFE4),
    textError: Color(0x80FFFFFF),
    lightSuccess: _successIndicator,
    lightError: _darkErrorIndicator,
  );

  static const light = AppSyncColors(
    text: Color(0xFF005B35),
    textSyncing: Color(0xA6001E0A),
    textError: Color(0x80141818),
    lightSuccess: _successIndicator,
    lightError: _lightErrorIndicator,
  );
}
