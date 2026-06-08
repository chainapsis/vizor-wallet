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
  static const p800Light = Color(0xFF2E3232);

  // Primitive/900 — lightest / inverse of ground.
  static const p900Dark = Color(0xFFFFFFFF);
  static const p900Light = Color(0xFF141818);

  // Primitive/Gray/Alpha tokens. These are explicit Figma exports, not
  // derived at runtime, because a few semantic alpha tokens intentionally
  // point at different ladder steps per mode.
  static const p0Alpha0Dark = Color(0x00141818);
  static const p0Alpha0Light = Color(0x00FFFFFF);

  static const p0Alpha5Dark = Color(0x0D141818);
  static const p0Alpha5Light = Color(0x0DFFFFFF);

  static const p0Alpha10Dark = Color(0x1A141818);
  static const p0Alpha10Light = Color(0x1AFFFFFF);

  static const p0Alpha15Dark = Color(0x26141818);
  static const p0Alpha15Light = Color(0x26FFFFFF);

  static const p0Alpha30Dark = Color(0x4D141818);
  static const p0Alpha30Light = Color(0x4DFFFFFF);

  static const p0Alpha50Dark = Color(0x80141818);
  static const p0Alpha50Light = Color(0x80FFFFFF);

  static const p150Alpha15Dark = Color(0x262D3232);
  static const p150Alpha15Light = Color(0x26E1E1E1);

  static const p300Alpha50Dark = Color(0x804D5252);
  static const p300Alpha35Light = Color(0x59B8B8B8);

  static const p400Alpha20Dark = Color(0x33626767);
  static const p400Alpha20Light = Color(0x339A9A9A);

  static const p400Alpha35Dark = Color(0x59626767);

  static const p900Alpha5Dark = Color(0x0DFFFFFF);
  static const p900Alpha5Light = Color(0x0D141818);

  static const p900Alpha10Dark = Color(0x1AFFFFFF);
  static const p900Alpha10Light = Color(0x1A141818);

  static const p900Alpha20Dark = Color(0x33FFFFFF);
  static const p900Alpha20Light = Color(0x33141818);
}

/// Brand crimson primitive ladder.
///
/// Current primary/accent color family in the Figma design system. Used by
/// primary buttons, shielded-address feedback, and brand focus rings.
abstract final class CrimsonPrimitives {
  static const p0Dark = Color(0xFF0F0709);
  static const p0Light = Color(0xFFFCF4F6);

  static const p50Dark = Color(0xFF180A0E);
  static const p50Light = Color(0xFFF8E2E7);

  static const p100Dark = Color(0xFF241015);
  static const p100Light = Color(0xFFF1C2CB);

  static const p150Dark = Color(0xFF36181F);
  static const p150Light = Color(0xFFE59AA8);

  static const p200Dark = Color(0xFF8A2D40);
  static const p200Light = Color(0xFFD67284);

  static const p300Dark = Color(0xFFAE3E55);
  static const p300Light = Color(0xFFC2546A);

  static const p400Dark = Color(0xFFC75C72);
  static const p400Light = Color(0xFFAE3E55);

  static const p500Dark = Color(0xFFD8829A);
  static const p500Light = Color(0xFF8A2D40);

  static const p600Dark = Color(0xFFE5A4B5);
  static const p600Light = Color(0xFF5F1E2C);

  static const p700Dark = Color(0xFFEFC3CE);
  static const p700Light = Color(0xFF3D131C);

  static const p800Dark = Color(0xFFF6DFE5);
  static const p800Light = Color(0xFF240B11);

  static const p900Dark = Color(0xFFFCF4F6);
  static const p900Light = Color(0xFF0F0709);

  static const p300Alpha35Dark = Color(0x59AE3E55);
  static const p300Alpha15Light = Color(0x26C2546A);
}

/// Utility plum primitive ladder.
///
/// Used for destructive actions and validation errors.
abstract final class PlumPrimitives {
  static const p0Dark = Color(0xFF0B060D);
  static const p0Light = Color(0xFFF6EDF8);

  static const p50Dark = Color(0xFF2D1835);
  static const p50Light = Color(0xFFE2CBE6);

  static const p100Dark = Color(0xFF492B54);
  static const p100Light = Color(0xFFC598CD);

  static const p150Dark = Color(0xFF583465);
  static const p150Light = Color(0xFFB67CC0);

  static const p200Dark = Color(0xFF6C4077);
  static const p200Light = Color(0xFFAC6CB7);

  static const p300Dark = Color(0xFF854E91);
  static const p300Light = Color(0xFF9A59A6);

  static const p400Dark = Color(0xFF9A59A6);
  static const p400Light = Color(0xFF854E91);

  static const p500Dark = Color(0xFFAC6CB7);
  static const p500Light = Color(0xFF6C4077);

  static const p600Dark = Color(0xFFB67CC0);
  static const p600Light = Color(0xFF583465);

  static const p700Dark = Color(0xFFC598CD);
  static const p700Light = Color(0xFF492B54);

  static const p800Dark = Color(0xFFE2CBE6);
  static const p800Light = Color(0xFF2D1835);

  static const p900Dark = Color(0xFFF6EDF8);
  static const p900Light = Color(0xFF0B060D);

  static const p400Alpha8Dark = Color(0x14B760C4);
  static const p400Alpha8Light = Color(0x14854E91);

  static const p400Alpha25Dark = Color(0x40B760C4);
  static const p400Alpha15Light = Color(0x26854E91);
}

/// Utility gold primitive ladder.
///
/// Used by the current Figma success/warning utility tokens.
abstract final class GoldPrimitives {
  static const p0Dark = Color(0xFF0E0905);
  static const p0Light = Color(0xFFFCF8F2);

  static const p50Dark = Color(0xFF180F08);
  static const p50Light = Color(0xFFF8EDDA);

  static const p100Dark = Color(0xFF241810);
  static const p100Light = Color(0xFFF2DCB8);

  static const p150Dark = Color(0xFF36251A);
  static const p150Light = Color(0xFFEAC890);

  static const p200Dark = Color(0xFF4D3624);
  static const p200Light = Color(0xFFDDB37A);

  static const p300Dark = Color(0xFF6E4E33);
  static const p300Light = Color(0xFFCD9F64);

  static const p400Dark = Color(0xFF956B45);
  static const p400Light = Color(0xFFB0844F);

  static const p500Dark = Color(0xFFCD9F64);
  static const p500Light = Color(0xFF956B45);

  static const p600Dark = Color(0xFFDDB37A);
  static const p600Light = Color(0xFF6E4E33);

  static const p700Dark = Color(0xFFEAC890);
  static const p700Light = Color(0xFF4D3624);

  static const p800Dark = Color(0xFFF5E0B8);
  static const p800Light = Color(0xFF241810);

  static const p900Dark = Color(0xFFFCF8F2);
  static const p900Light = Color(0xFF0E0905);

  static const p400Alpha25Dark = Color(0x40956B45);
  static const p300Alpha25Light = Color(0x40CD9F64);
}

/// Utility green primitive ladder.
///
/// Reserved for positive states that need an explicitly green affordance.
abstract final class GreenPrimitives {
  static const p0Dark = Color(0xFF031203);
  static const p0Light = Color(0xFFF0FAF0);

  static const p50Dark = Color(0xFF071A07);
  static const p50Light = Color(0xFFE9FBE9);

  static const p100Dark = Color(0xFF0D270D);
  static const p100Light = Color(0xFFB8E8B8);

  static const p150Dark = Color(0xFF153815);
  static const p150Light = Color(0xFF92D892);

  static const p200Dark = Color(0xFF1E4F1E);
  static const p200Light = Color(0xFF6BCC6B);

  static const p300Dark = Color(0xFF2D7A2D);
  static const p300Light = Color(0xFF47BE47);

  static const p400Dark = Color(0xFF47BE47);
  static const p400Light = Color(0xFF2D7A2D);

  static const p500Dark = Color(0xFF6BCC6B);
  static const p500Light = Color(0xFF1E4F1E);

  static const p600Dark = Color(0xFF92D892);
  static const p600Light = Color(0xFF153815);

  static const p700Dark = Color(0xFFB8E8B8);
  static const p700Light = Color(0xFF0D270D);

  static const p800Dark = Color(0xFFE9FBE9);
  static const p800Light = Color(0xFF071A07);

  static const p900Dark = Color(0xFFF0FAF0);
  static const p900Light = Color(0xFF031203);
}
