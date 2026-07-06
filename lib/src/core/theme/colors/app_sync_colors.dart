import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Sync-specific sidebar colors retained from the OLDSemantic sync tokens.
class AppSyncColors {
  const AppSyncColors({
    required this.text,
    required this.textSyncing,
    required this.textSyncingHighlight,
    required this.textError,
    required this.glow,
    required this.lightSyncing,
    required this.lightSuccess,
    required this.lightError,
  });

  final Color text;
  final Color textSyncing;
  final Color textSyncingHighlight;
  final Color textError;
  final Color glow;
  final Color lightSyncing;
  final Color lightSuccess;
  final Color lightError;

  static const dark = AppSyncColors(
    text: GreenPrimitives.p900Dark,
    textSyncing: Primitives.p600Dark,
    textSyncingHighlight: Primitives.p900Dark,
    textError: Primitives.p900Alpha50Dark,
    glow: Primitives.p500Dark,
    lightSyncing: Primitives.p600Dark,
    lightSuccess: GreenPrimitives.p300Dark,
    lightError: Primitives.p600Dark,
  );

  static const light = AppSyncColors(
    text: GreenPrimitives.p700Light,
    textSyncing: Primitives.p600Dark,
    textSyncingHighlight: Primitives.p900Dark,
    textError: Primitives.p900Alpha50Light,
    glow: GreenPrimitives.p200Light,
    lightSyncing: Primitives.p600Dark,
    lightSuccess: GreenPrimitives.p400Light,
    lightError: Primitives.p500Light,
  );
}
