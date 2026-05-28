import 'package:flutter/painting.dart';

/// Raw color primitives from the Zcash design system Figma spec.
///
/// 12-step neutral ladder. Each step has a dark-mode face (`*Dark`) and a
/// light-mode face (`*Light`). Semantic tokens under `colors/` pick the
/// appropriate face per mode — they do **not** always share the same
/// primitive step across modes (e.g. `border.subtle` uses `p150Dark` and
/// `p150Light`, while text tokens reach opposite ends of the ladder).
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
  static const p50Light = Color(0xFFF7F7F7);

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
  static const p800Dark = Color(0xFFF7F7F7);
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

  static const p300Alpha10Dark = Color(0x1A4D5252);
  static const p300Alpha10Light = Color(0x1AB8B8B8);

  static const p300Alpha15Dark = Color(0x264D5252);
  static const p300Alpha15Light = Color(0x26B8B8B8);

  static const p300Alpha20Dark = Color(0x334D5252);
  static const p300Alpha20Light = Color(0x33B8B8B8);

  static const p300Alpha35Dark = Color(0x594D5252);
  static const p300Alpha35Light = Color(0x59B8B8B8);

  static const p300Alpha50Dark = Color(0x804D5252);
  static const p300Alpha50Light = Color(0x80B8B8B8);

  static const p400Alpha20Dark = Color(0x33626767);
  static const p400Alpha20Light = Color(0x339A9A9A);

  static const p400Alpha35Dark = Color(0x59626767);
  static const p400Alpha35Light = Color(0x599A9A9A);

  static const p700Alpha50Dark = Color(0x80C2C3C3);
  static const p700Alpha50Light = Color(0x804D5252);

  static const p900Alpha5Dark = Color(0x0DFFFFFF);
  static const p900Alpha5Light = Color(0x0D141818);

  static const p900Alpha10Dark = Color(0x1AFFFFFF);
  static const p900Alpha10Light = Color(0x1A141818);

  static const p900Alpha20Dark = Color(0x33FFFFFF);
  static const p900Alpha20Light = Color(0x33141818);

  static const p900Alpha50Dark = Color(0x80FFFFFF);
  static const p900Alpha50Light = Color(0x80141818);
}

/// Brand crimson primitive ladder.
///
/// Current primary/accent color family in the Figma design system. Used by
/// primary buttons, shielded-address feedback, and brand focus rings.
abstract final class CrimsonPrimitives {
  static const p0Dark = Color(0xFF080305);
  static const p0Light = Color(0xFFF6EBEF);

  static const p50Dark = Color(0xFF19080F);
  static const p50Light = Color(0xFFE1B9C8);

  static const p100Dark = Color(0xFF32111D);
  static const p100Light = Color(0xFFCF92A8);

  static const p150Dark = Color(0xFF4C192C);
  static const p150Light = Color(0xFFBE6A88);

  static const p200Dark = Color(0xFF6D243F);
  static const p200Light = Color(0xFFB35074);

  static const p300Dark = Color(0xFF862D4E);
  static const p300Light = Color(0xFFA83861);

  static const p400Dark = Color(0xFFA83861);
  static const p400Light = Color(0xFF862D4E);

  static const p500Dark = Color(0xFFB35074);
  static const p500Light = Color(0xFF6D243F);

  static const p600Dark = Color(0xFFBE6A88);
  static const p600Light = Color(0xFF4C192C);

  static const p700Dark = Color(0xFFCF92A8);
  static const p700Light = Color(0xFF32111D);

  static const p800Dark = Color(0xFFE1B9C8);
  static const p800Light = Color(0xFF19080F);

  static const p900Dark = Color(0xFFF5EBEE);
  static const p900Light = Color(0xFF080305);

  static const p300Alpha10Dark = Color(0x1A862D4E);
  static const p300Alpha10Light = Color(0x1AA83861);

  static const p300Alpha15Dark = Color(0x26862D4E);
  static const p300Alpha15Light = Color(0x26A83861);

  static const p300Alpha25Dark = Color(0x40862D4E);
  static const p300Alpha25Light = Color(0x40A83861);

  static const p300Alpha35Dark = Color(0x59862D4E);
  static const p300Alpha35Light = Color(0x59A83861);

  static const p400Alpha15Dark = Color(0x26A83861);
  static const p400Alpha15Light = Color(0x26862D4E);

  static const p400Alpha25Dark = Color(0x40A83861);
  static const p400Alpha25Light = Color(0x40862D4E);

  static const p400Alpha35Dark = Color(0x59A83861);
  static const p400Alpha35Light = Color(0x59862D4E);
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

  static const p400Alpha4Dark = Color(0x0AB760C4);
  static const p400Alpha4Light = Color(0x0A854E91);

  static const p400Alpha8Dark = Color(0x14B760C4);
  static const p400Alpha8Light = Color(0x14854E91);

  static const p400Alpha15Dark = Color(0x26B760C4);
  static const p400Alpha15Light = Color(0x26854E91);

  static const p400Alpha25Dark = Color(0x40B760C4);
  static const p400Alpha25Light = Color(0x40854E91);
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

  static const p300Alpha15Dark = Color(0x266E4E33);
  static const p300Alpha15Light = Color(0x26CD9F64);

  static const p300Alpha25Dark = Color(0x406E4E33);
  static const p300Alpha25Light = Color(0x40CD9F64);

  static const p300Alpha35Dark = Color(0x596E4E33);
  static const p300Alpha35Light = Color(0x59CD9F64);

  static const p400Alpha15Dark = Color(0x26956B45);
  static const p400Alpha15Light = Color(0x26B0844F);

  static const p400Alpha25Dark = Color(0x40956B45);
  static const p400Alpha25Light = Color(0x40B0844F);

  static const p400Alpha35Dark = Color(0x59956B45);
  static const p400Alpha35Light = Color(0x59B0844F);
}

/// Utility green primitive ladder.
///
/// Reserved for positive states that need an explicitly green affordance.
abstract final class GreenPrimitives {
  static const p0Dark = Color(0xFF001E0A);
  static const p0Light = Color(0xFFD3FFE4);

  static const p50Dark = Color(0xFF023A21);
  static const p50Light = Color(0xFFC2F5D5);

  static const p100Dark = Color(0xFF005B35);
  static const p100Light = Color(0xFFA9ECC4);

  static const p150Dark = Color(0xFF007F49);
  static const p150Light = Color(0xFF89E5B0);

  static const p200Dark = Color(0xFF00A460);
  static const p200Light = Color(0xFF64DD9C);

  static const p300Dark = Color(0xFF0DC87D);
  static const p300Light = Color(0xFF3BD38B);

  static const p400Dark = Color(0xFF3BD38B);
  static const p400Light = Color(0xFF0DC87D);

  static const p500Dark = Color(0xFF64DD9C);
  static const p500Light = Color(0xFF00A460);

  static const p600Dark = Color(0xFF89E5B0);
  static const p600Light = Color(0xFF007F49);

  static const p700Dark = Color(0xFFA9ECC4);
  static const p700Light = Color(0xFF005B35);

  static const p800Dark = Color(0xFFC2F5D5);
  static const p800Light = Color(0xFF023A21);

  static const p900Dark = Color(0xFFD3FFE4);
  static const p900Light = Color(0xFF001E0A);

  static const p300Alpha15Dark = Color(0x260DC87D);
  static const p300Alpha15Light = Color(0x263BD38B);

  static const p300Alpha25Dark = Color(0x400DC87D);
  static const p300Alpha25Light = Color(0x403BD38B);

  static const p400Alpha15Dark = Color(0x263BD38B);
  static const p400Alpha15Light = Color(0x260DC87D);

  static const p400Alpha25Dark = Color(0x403BD38B);
  static const p400Alpha25Light = Color(0x400DC87D);

  static const p900Alpha50Dark = Color(0x80D3FFE4);
  static const p900Alpha50Light = Color(0x80001E0A);

  static const p900Alpha65Dark = Color(0xA6D3FFE4);
  static const p900Alpha65Light = Color(0xA6001E0A);
}
