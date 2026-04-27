import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Fade / scrim tokens.
///
/// * [illustration] — Gentle fade laid over a bottom-anchored
///   illustration so the art dissolves into the backdrop instead of
///   presenting a hard top edge. Dark mode uses a 50% overlay of the
///   ground color; light mode is fully transparent (the illustration
///   sits directly on the light surface and needs no darkening).
class AppFadeColors {
  const AppFadeColors({required this.illustration});

  final Color illustration;

  static const dark = AppFadeColors(illustration: Primitives.p0Alpha50Dark);

  // Fully transparent on light mode — keeps the same rgb anchor as the
  // dark face so fade animations between modes don't flicker through a
  // neutral color.
  static const light = AppFadeColors(illustration: Primitives.p0Alpha0Dark);
}
