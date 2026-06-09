import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Shadow colors from the redesign `Semantic/Shadows` tokens.
class AppShadowColors {
  const AppShadowColors({
    required this.shadow1,
    required this.shadow2,
    required this.shadow3,
    required this.subtle,
    required this.regular,
  });

  final Color shadow1;
  final Color shadow2;
  final Color shadow3;
  final Color subtle;
  final Color regular;

  static const dark = AppShadowColors(
    shadow1: Primitives.p0Alpha0Dark,
    shadow2: Primitives.p0Alpha0Dark,
    shadow3: Primitives.p0Alpha0Dark,
    subtle: Primitives.p0Alpha0Dark,
    regular: Primitives.p0Alpha0Dark,
  );

  static const light = AppShadowColors(
    shadow1: Primitives.p150Light,
    shadow2: Primitives.p300Light,
    shadow3: Primitives.p900Alpha20Light,
    subtle: Primitives.p900Alpha5Light,
    regular: Primitives.p900Alpha10Light,
  );
}
