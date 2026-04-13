import 'package:flutter/painting.dart';

/// Raw color primitives from the Zcash design system Figma spec.
///
/// 12-step neutral ladder. Each step has a dark-mode face (`*Dark`) and a
/// light-mode face (`*Light`). Semantic tokens under `colors/` pick the
/// appropriate face per mode — they do **not** always share the same
/// primitive step across modes (e.g. `bg/base` uses `p50Dark` but `p0Light`).
///
/// Widgets must never reference these directly. Route through the semantic
/// categories in [AppColors] so roles stay decoupled from the palette.
abstract final class Primitives {
  // Primitive/0 — darkest anchor / inverse of lightest.
  static const p0Dark = Color(0xFF151818);
  static const p0Light = Color(0xFFFFFFFF);

  // Primitive/50 — base surface.
  static const p50Dark = Color(0xFF1C1F1F);
  static const p50Light = Color(0xFFF5F5F5);

  // Primitive/100 — raised surface.
  static const p100Dark = Color(0xFF242828);
  static const p100Light = Color(0xFFEBEBEB);

  // Primitive/150 — overlay / accent surface.
  static const p150Dark = Color(0xFF2E3232);
  static const p150Light = Color(0xFFE1E1E1);

  // Primitive/200 — subtle border.
  static const p200Dark = Color(0xFF3A3E3E);
  static const p200Light = Color(0xFFD4D4D4);

  // Primitive/300 — default border / disabled icon.
  static const p300Dark = Color(0xFF4E5252);
  static const p300Light = Color(0xFFB8B8B8);

  // Primitive/400 — strong border / disabled text.
  static const p400Dark = Color(0xFF636767);
  static const p400Light = Color(0xFF9A9A9A);

  // Primitive/500 — mid-gray. Identical in both modes by design.
  static const p500Dark = Color(0xFF858686);
  static const p500Light = Color(0xFF858686);

  // Primitive/600 — secondary text.
  static const p600Dark = Color(0xFFA3A4A4);
  static const p600Light = Color(0xFF636767);

  // Primitive/700 — primary text.
  static const p700Dark = Color(0xFFC2C3C3);
  static const p700Light = Color(0xFF4E5252);

  // Primitive/800 — accent / primary button fill.
  static const p800Dark = Color(0xFFE1E1E1);
  static const p800Light = Color(0xFF3A3E3E);

  // Primitive/900 — lightest / inverse of ground.
  static const p900Dark = Color(0xFFFFFFFF);
  static const p900Light = Color(0xFF151818);
}

/// Brand purple primitive ladder (12 steps).
///
/// Same mirrored pattern as [Primitives]: `*Dark.p(N)` equals
/// `*Light.p(900-N)` in every step, so the same semantic token can reference
/// step N in both modes while yielding mode-appropriate values. Used by the
/// primary button fill, brand text/icon tokens, and the brand focus ring.
abstract final class PurplePrimitives {
  static const p0Dark = Color(0xFF1A0B1C);
  static const p0Light = Color(0xFFF9E5FB);

  static const p50Dark = Color(0xFF240F27);
  static const p50Light = Color(0xFFF0BCF4);

  static const p100Dark = Color(0xFF351535);
  static const p100Light = Color(0xFFE799EE);

  static const p150Dark = Color(0xFF4A1D4D);
  static const p150Light = Color(0xFFDE77E9);

  static const p200Dark = Color(0xFF612462);
  static const p200Light = Color(0xFFD657E4);

  static const p300Dark = Color(0xFF8C2E90);
  static const p300Light = Color(0xFFB83FBF);

  static const p400Dark = Color(0xFFB83FBF);
  static const p400Light = Color(0xFF8C2E90);

  static const p500Dark = Color(0xFFD657E4);
  static const p500Light = Color(0xFF612462);

  static const p600Dark = Color(0xFFDE77E9);
  static const p600Light = Color(0xFF4A1D4D);

  static const p700Dark = Color(0xFFE799EE);
  static const p700Light = Color(0xFF351535);

  static const p800Dark = Color(0xFFF0BCF4);
  static const p800Light = Color(0xFF240F27);

  static const p900Dark = Color(0xFFF9E5FB);
  static const p900Light = Color(0xFF1A0B1C);
}

/// Brand cyan primitive ladder (12 steps).
///
/// Same mirrored structure as [PurplePrimitives]. Used by brand text/icon
/// tokens; not used by buttons or focus rings in the current design.
abstract final class CyanPrimitives {
  static const p0Dark = Color(0xFF031419);
  static const p0Light = Color(0xFFD0F2F7);

  static const p50Dark = Color(0xFF051D22);
  static const p50Light = Color(0xFF95DEE8);

  static const p100Dark = Color(0xFF072A31);
  static const p100Light = Color(0xFF5CCBDB);

  static const p150Dark = Color(0xFF0A3A44);
  static const p150Light = Color(0xFF2BB5CC);

  static const p200Dark = Color(0xFF0D4E5C);
  static const p200Light = Color(0xFF0C9EB9);

  static const p300Dark = Color(0xFF0D7187);
  static const p300Light = Color(0xFF0C8FAC);

  static const p400Dark = Color(0xFF0C8FAC);
  static const p400Light = Color(0xFF0D7187);

  static const p500Dark = Color(0xFF0C9EB9);
  static const p500Light = Color(0xFF0D4E5C);

  static const p600Dark = Color(0xFF2BB5CC);
  static const p600Light = Color(0xFF0A3A44);

  static const p700Dark = Color(0xFF5CCBDB);
  static const p700Light = Color(0xFF072A31);

  static const p800Dark = Color(0xFF95DEE8);
  static const p800Light = Color(0xFF051D22);

  static const p900Dark = Color(0xFFD0F2F7);
  static const p900Light = Color(0xFF031419);
}
