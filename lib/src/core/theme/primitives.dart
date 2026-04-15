import 'package:flutter/painting.dart';

/// Raw color primitives from the Zcash design system Figma spec.
///
/// 12-step neutral ladder. Each step has a dark-mode face (`*Dark`) and a
/// light-mode face (`*Light`). Semantic tokens under `colors/` pick the
/// appropriate face per mode — they do **not** always share the same
/// primitive step across modes (e.g. `border.subtle` uses `p200Dark` but
/// `p150Light`).
///
/// Values come from the Figma Dark/Light token JSON exports after the file
/// was converted from Display P3 to sRGB with "Keep appearance", so the
/// hex values are the sRGB approximations that preserve the visual intent
/// of the original P3 design.
///
/// Widgets must never reference these directly. Route through the semantic
/// categories in [AppColors] so roles stay decoupled from the palette.
abstract final class Primitives {
  // Primitive/0 — darkest anchor / inverse of lightest.
  static const p0Dark = Color(0xFF141818);
  static const p0Light = Color(0xFFFFFFFF);

  // Primitive/50 — base surface.
  static const p50Dark = Color(0xFF1B1F1F);
  static const p50Light = Color(0xFFF5F5F5);

  // Primitive/100 — raised surface.
  static const p100Dark = Color(0xFF232828);
  static const p100Light = Color(0xFFEBEBEB);

  // Primitive/150 — overlay / accent surface.
  static const p150Dark = Color(0xFF2D3232);
  static const p150Light = Color(0xFFE1E1E1);

  // Primitive/200 — subtle border.
  static const p200Dark = Color(0xFF393E3E);
  static const p200Light = Color(0xFFD4D4D4);

  // Primitive/300 — default border / disabled icon.
  static const p300Dark = Color(0xFF4D5252);
  static const p300Light = Color(0xFFB8B8B8);

  // Primitive/400 — strong border / disabled text.
  static const p400Dark = Color(0xFF626767);
  static const p400Light = Color(0xFF9A9A9A);

  // Primitive/500 — mid-gray. Identical in both modes by design.
  static const p500Dark = Color(0xFF858686);
  static const p500Light = Color(0xFF858686);

  // Primitive/600 — secondary text.
  static const p600Dark = Color(0xFFA3A4A4);
  static const p600Light = Color(0xFF626767);

  // Primitive/700 — primary text.
  static const p700Dark = Color(0xFFC2C3C3);
  static const p700Light = Color(0xFF4D5252);

  // Primitive/800 — accent / primary button fill.
  static const p800Dark = Color(0xFFE1E1E1);
  static const p800Light = Color(0xFF393E3E);

  // Primitive/900 — lightest / inverse of ground.
  static const p900Dark = Color(0xFFFFFFFF);
  static const p900Light = Color(0xFF141818);

  // Primitive/0 at 50% alpha — used as a scrim/fade primitive over
  // illustrations and content that needs to dim into the background.
  // Mode-invariant by design (the alpha carries the fade, the base
  // color doesn't flip).
  static const p0Alpha50Dark = Color(0x80141818);
  static const p0Alpha50Light = Color(0x80141818);
}

/// Brand purple primitive ladder (12 steps).
///
/// Same mirrored pattern as [Primitives]: `*Dark.p(N)` equals
/// `*Light.p(900-N)` in every step, so the same semantic token can reference
/// step N in both modes while yielding mode-appropriate values. Used by the
/// primary button fill, brand text/icon tokens, and the brand focus ring.
abstract final class PurplePrimitives {
  static const p0Dark = Color(0xFF1C0A1D);
  static const p0Light = Color(0xFFFDE4FD);

  static const p50Dark = Color(0xFF270E28);
  static const p50Light = Color(0xFFFAB9F8);

  static const p100Dark = Color(0xFF3A1337);
  static const p100Light = Color(0xFFF494F3);

  static const p150Dark = Color(0xFF50194F);
  static const p150Light = Color(0xFFEE70EF);

  static const p200Dark = Color(0xFF691F65);
  static const p200Light = Color(0xFFE74BEB);

  static const p300Dark = Color(0xFF982495);
  static const p300Light = Color(0xFFC832C5);

  static const p400Dark = Color(0xFFC832C5);
  static const p400Light = Color(0xFF982495);

  static const p500Dark = Color(0xFFE74BEB);
  static const p500Light = Color(0xFF691F65);

  static const p600Dark = Color(0xFFEE70EF);
  static const p600Light = Color(0xFF50194F);

  static const p700Dark = Color(0xFFF494F3);
  static const p700Light = Color(0xFF3A1337);

  static const p800Dark = Color(0xFFFAB9F8);
  static const p800Light = Color(0xFF270E28);

  static const p900Dark = Color(0xFFFDE4FD);
  static const p900Light = Color(0xFF1C0A1D);
}

/// Brand cyan primitive ladder (12 steps).
///
/// Same mirrored structure as [PurplePrimitives]. Used by brand text/icon
/// tokens; not used by buttons or focus rings in the current design.
abstract final class CyanPrimitives {
  static const p0Dark = Color(0xFF00151A);
  static const p0Light = Color(0xFFEBFDFF);

  static const p50Dark = Color(0xFF001E23);
  static const p50Light = Color(0xFF7DE0EA);

  static const p100Dark = Color(0xFF002B32);
  static const p100Light = Color(0xFF00CEDE);

  static const p150Dark = Color(0xFF003B45);
  static const p150Light = Color(0xFF00B8CF);

  static const p200Dark = Color(0xFF00505E);
  static const p200Light = Color(0xFF00A1BC);

  static const p300Dark = Color(0xFF00738A);
  static const p300Light = Color(0xFF0092AF);

  static const p400Dark = Color(0xFF0092AF);
  static const p400Light = Color(0xFF00738A);

  static const p500Dark = Color(0xFF00A1BC);
  static const p500Light = Color(0xFF00505E);

  static const p600Dark = Color(0xFF00B8CF);
  static const p600Light = Color(0xFF003B45);

  static const p700Dark = Color(0xFF00CEDE);
  static const p700Light = Color(0xFF002B32);

  static const p800Dark = Color(0xFF7DE0EA);
  static const p800Light = Color(0xFF001E23);

  static const p900Dark = Color(0xFFEBFDFF);
  static const p900Light = Color(0xFF00151A);
}

/// Brand yellow primitive ladder (12 steps).
///
/// Same mirrored structure as [PurplePrimitives] / [CyanPrimitives].
/// Used by warning text/icon tokens; reserved for future warning
/// surfaces/borders.
abstract final class YellowPrimitives {
  static const p0Dark = Color(0xFF1A0E00);
  static const p0Light = Color(0xFFFFF8EC);

  static const p50Dark = Color(0xFF231400);
  static const p50Light = Color(0xFFFEEFD4);

  static const p100Dark = Color(0xFF331D00);
  static const p100Light = Color(0xFFFDD9A0);

  static const p150Dark = Color(0xFF4A2900);
  static const p150Light = Color(0xFFFCBF5C);

  static const p200Dark = Color(0xFF663800);
  static const p200Light = Color(0xFFFFA832);

  static const p300Dark = Color(0xFF994F00);
  static const p300Light = Color(0xFFFF9617);

  static const p400Dark = Color(0xFFFF9617);
  static const p400Light = Color(0xFFE07800);

  static const p500Dark = Color(0xFFFFAD47);
  static const p500Light = Color(0xFF994F00);

  static const p600Dark = Color(0xFFFFC470);
  static const p600Light = Color(0xFF663800);

  static const p700Dark = Color(0xFFFFD99F);
  static const p700Light = Color(0xFF4A2900);

  static const p800Dark = Color(0xFFFEEFD4);
  static const p800Light = Color(0xFF331D00);

  static const p900Dark = Color(0xFFFFF8EC);
  static const p900Light = Color(0xFF1A0E00);
}
