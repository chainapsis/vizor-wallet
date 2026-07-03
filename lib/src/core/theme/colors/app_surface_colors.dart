import 'package:flutter/painting.dart';

import '../primitives.dart';

/// Component-level surface colors.
///
/// * [card] — Card components, list rows.
/// * [input] — Text input background at rest.
/// * [inputFocus] — Text input when focused.
/// * [nav] — Navigation rail background.
/// * [navActive] — Active nav item indicator.
/// * [tooltip] — Tooltip / popover background. Theme-invariant.
/// * [qrCode] — QR code backing surface. Theme-invariant for scan contrast.
/// * [scrollbarThumb] — Desktop pane overlay scrollbar thumb. Solid (fully
///   opaque) per the Figma Scrollbar component: `#393E3E` dark / `#E1E1E1`
///   light. Distinct from the sidebar accounts scrollbar, which uses the
///   semi-transparent `background.neutralStrongOpacity` token.
class AppSurfaceColors {
  const AppSurfaceColors({
    required this.card,
    required this.input,
    required this.inputFocus,
    required this.nav,
    required this.navActive,
    required this.tooltip,
    required this.qrCode,
    required this.scrollbarThumb,
  });

  final Color card;
  final Color input;
  final Color inputFocus;
  final Color nav;
  final Color navActive;
  final Color tooltip;
  final Color qrCode;
  final Color scrollbarThumb;

  static const dark = AppSurfaceColors(
    card: Primitives.p100Dark,
    input: Primitives.p50Dark,
    inputFocus: Primitives.p100Dark,
    nav: Primitives.p50Dark,
    navActive: Primitives.p150Dark,
    tooltip: Primitives.p200Dark,
    qrCode: Primitives.p0Light,
    scrollbarThumb: Primitives.p200Dark,
  );

  static const light = AppSurfaceColors(
    card: Primitives.p50Light,
    input: Primitives.p0Light,
    inputFocus: Primitives.p50Light,
    nav: Primitives.p0Light,
    navActive: Primitives.p100Light,
    // Tooltip is the same concrete value in both modes; picking p800Light here
    // keeps the expression inside the light-face lookup.
    tooltip: Primitives.p800Light,
    qrCode: Primitives.p0Light,
    scrollbarThumb: Primitives.p150Light,
  );
}
