import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Sync-specific sidebar colors retained from the OLDSemantic sync tokens.
class AppSyncColors {
  const AppSyncColors({
    required this.text,
    required this.textSyncing,
    required this.textError,
    required this.glow,
    required this.lightSuccess,
    required this.lightError,
  });

  final Color text;
  final Color textSyncing;
  final Color textError;
  final Color glow;
  final Color lightSuccess;
  final Color lightError;

  static const dark = AppSyncColors(
    text: GreenPrimitives.p900Dark,
    textSyncing: GreenPrimitives.p900Alpha65Dark,
    textError: Primitives.p900Alpha50Dark,
    glow: Primitives.p500Dark,
    lightSuccess: GreenPrimitives.p300Dark,
    lightError: Primitives.p600Dark,
  );

  static const light = AppSyncColors(
    text: GreenPrimitives.p700Light,
    textSyncing: GreenPrimitives.p900Alpha65Light,
    textError: Primitives.p900Alpha50Light,
    glow: GreenPrimitives.p200Light,
    lightSuccess: GreenPrimitives.p400Light,
    lightError: Primitives.p500Light,
  );
}
