import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Shadow colors from the redesign `Semantic/Shadows` tokens.
class AppShadowColors {
  const AppShadowColors({required this.subtle, required this.regular});

  final Color subtle;
  final Color regular;

  static const dark = AppShadowColors(
    subtle: Primitives.p0Alpha0Dark,
    regular: Primitives.p0Alpha0Dark,
  );

  static const light = AppShadowColors(
    subtle: Primitives.p900Alpha5Light,
    regular: Primitives.p900Alpha10Light,
  );
}
