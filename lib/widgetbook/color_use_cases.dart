import 'package:flutter/widgets.dart';

import '../src/core/theme/colors/app_colors.dart';
import '../src/core/theme/primitives.dart';
import 'color_swatch.dart';

// Each builder below returns a ColorCategoryPage for one Figma color sheet.
// The dark/light values are pulled straight from AppColors.dark / .light so
// the Widgetbook always mirrors the token truth — if the token file changes,
// the swatch updates automatically.

Widget buildPrimitivesUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives',
    swatches: [
      TokenSwatch(name:'_ Primitive/0', description: 'Darkest anchor — ground & inverse text', dark: Primitives.p0Dark, light: Primitives.p0Light),
      TokenSwatch(name:'_ Primitive/50', description: 'Base surface dark', dark: Primitives.p50Dark, light: Primitives.p50Light),
      TokenSwatch(name:'_ Primitive/100', description: 'Raised surface dark', dark: Primitives.p100Dark, light: Primitives.p100Light),
      TokenSwatch(name:'_ Primitive/150', description: 'Overlay / accent surface', dark: Primitives.p150Dark, light: Primitives.p150Light),
      TokenSwatch(name:'_ Primitive/200', description: 'Subtle border dark', dark: Primitives.p200Dark, light: Primitives.p200Light),
      TokenSwatch(name:'_ Primitive/300', description: 'Default border dark', dark: Primitives.p300Dark, light: Primitives.p300Light),
      TokenSwatch(name:'_ Primitive/400', description: 'Strong border / disabled text', dark: Primitives.p400Dark, light: Primitives.p400Light),
      TokenSwatch(name:'_ Primitive/500', description: 'Mid-gray — same both modes', dark: Primitives.p500Dark, light: Primitives.p500Light),
      TokenSwatch(name:'_ Primitive/600', description: 'Secondary text dark', dark: Primitives.p600Dark, light: Primitives.p600Light),
      TokenSwatch(name:'_ Primitive/700', description: 'Primary text dark', dark: Primitives.p700Dark, light: Primitives.p700Light),
      TokenSwatch(name:'_ Primitive/800', description: 'Accent / primary button dark', dark: Primitives.p800Dark, light: Primitives.p800Light),
      TokenSwatch(name:'_ Primitive/900', description: 'Lightest — inverse of ground', dark: Primitives.p900Dark, light: Primitives.p900Light),
    ],
  );
}

Widget buildBackgroundUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Background',
    swatches: [
      TokenSwatch(name:'bg/ground', description: 'Deepest layer — Scaffold background', dark: d.background.ground, light: l.background.ground),
      TokenSwatch(name:'bg/base', description: 'Primary content surface, main panels', dark: d.background.base, light: l.background.base),
      TokenSwatch(name:'bg/raised', description: 'Cards, modals, sidebars, drawers', dark: d.background.raised, light: l.background.raised),
      TokenSwatch(name:'bg/overlay', description: 'Dropdowns, popovers, floating elements', dark: d.background.overlay, light: l.background.overlay),
    ],
  );
}

Widget buildSurfaceUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Surface',
    swatches: [
      TokenSwatch(name:'surface/card', description: 'Card components, list rows', dark: d.surface.card, light: l.surface.card),
      TokenSwatch(name:'surface/input', description: 'Text input background at rest', dark: d.surface.input, light: l.surface.input),
      TokenSwatch(name:'surface/input-focus', description: 'Text input when focused', dark: d.surface.inputFocus, light: l.surface.inputFocus),
      TokenSwatch(name:'surface/nav', description: 'Navigation rail background', dark: d.surface.nav, light: l.surface.nav),
      TokenSwatch(name:'surface/nav-active', description: 'Active nav item indicator', dark: d.surface.navActive, light: l.surface.navActive),
      TokenSwatch(name:'surface/tooltip', description: 'Tooltip / popover background', dark: d.surface.tooltip, light: l.surface.tooltip),
    ],
  );
}

Widget buildBorderUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Border',
    swatches: [
      TokenSwatch(name:'border/subtle', description: 'Hairline dividers, row separators', dark: d.border.subtle, light: l.border.subtle),
      TokenSwatch(name:'border/regular', description: 'Input fields, cards, chips', dark: d.border.regular, light: l.border.regular),
      TokenSwatch(name:'border/strong', description: 'Selected states, active tabs', dark: d.border.strong, light: l.border.strong),
    ],
  );
}

Widget buildTextUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Text',
    swatches: [
      TokenSwatch(name:'text/accent', description: 'Titles, headings, max contrast', dark: d.text.accent, light: l.text.accent),
      TokenSwatch(name:'text/primary', description: 'Default body text, paragraphs', dark: d.text.primary, light: l.text.primary),
      TokenSwatch(name:'text/secondary', description: 'Subtitles, timestamps, metadata', dark: d.text.secondary, light: l.text.secondary),
      TokenSwatch(name:'text/muted', description: 'Descriptions — same both modes', dark: d.text.muted, light: l.text.muted),
      TokenSwatch(name:'text/disabled', description: 'Inactive, unavailable labels', dark: d.text.disabled, light: l.text.disabled),
      TokenSwatch(name:'text/inverse', description: 'Text on inverted surfaces', dark: d.text.inverse, light: l.text.inverse),
    ],
  );
}

Widget buildIconUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Icon',
    swatches: [
      TokenSwatch(name:'icon/accent', description: 'Active, selected, primary icons', dark: d.icon.accent, light: l.icon.accent),
      TokenSwatch(name:'icon/regular', description: 'Standard UI icons', dark: d.icon.regular, light: l.icon.regular),
      TokenSwatch(name:'icon/muted', description: 'Inactive, decorative icons', dark: d.icon.muted, light: l.icon.muted),
      TokenSwatch(name:'icon/disabled', description: 'Disabled control icons', dark: d.icon.disabled, light: l.icon.disabled),
      TokenSwatch(name:'icon/inverse', description: 'Icons on inverted surfaces', dark: d.icon.inverse, light: l.icon.inverse),
      TokenSwatch(name:'icon/on-primary', description: 'Icons inside primary button', dark: d.icon.onPrimary, light: l.icon.onPrimary),
    ],
  );
}

Widget buildButtonPrimaryUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Button / Primary',
    swatches: [
      TokenSwatch(name:'button/primary/bg', description: 'Fill at rest', dark: d.button.primary.bg, light: l.button.primary.bg),
      TokenSwatch(name:'button/primary/bg-hover', description: 'Fill on hover', dark: d.button.primary.bgHover, light: l.button.primary.bgHover),
      TokenSwatch(name:'button/primary/bg-pressed', description: 'Fill on press', dark: d.button.primary.bgPressed, light: l.button.primary.bgPressed),
      TokenSwatch(name:'button/primary/label', description: 'Label inside primary button', dark: d.button.primary.label, light: l.button.primary.label),
    ],
  );
}

Widget buildButtonSecondaryUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Button / Secondary',
    swatches: [
      TokenSwatch(name:'button/secondary/bg', description: 'Fill at rest', dark: d.button.secondary.bg, light: l.button.secondary.bg),
      TokenSwatch(name:'button/secondary/bg-hover', description: 'Fill on hover', dark: d.button.secondary.bgHover, light: l.button.secondary.bgHover),
      TokenSwatch(name:'button/secondary/bg-pressed', description: 'Fill on press', dark: d.button.secondary.bgPressed, light: l.button.secondary.bgPressed),
      TokenSwatch(name:'button/secondary/label', description: 'Label inside secondary button', dark: d.button.secondary.label, light: l.button.secondary.label),
    ],
  );
}

Widget buildButtonGhostDestructiveUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Button / Ghost & Destructive',
    swatches: [
      TokenSwatch(name:'button/ghost/bg', description: 'Transparent base', dark: d.button.ghost.bg, light: l.button.ghost.bg),
      TokenSwatch(name:'button/ghost/bg-hover', description: 'Tint on hover', dark: d.button.ghost.bgHover, light: l.button.ghost.bgHover),
      TokenSwatch(name:'button/ghost/border', description: 'Ghost border (primary affordance)', dark: d.button.ghost.border, light: l.button.ghost.border),
      TokenSwatch(name:'button/ghost/label', description: 'Ghost label', dark: d.button.ghost.label, light: l.button.ghost.label),
      TokenSwatch(name:'button/destructive/bg', description: 'Destructive fill (delete, wipe)', dark: d.button.destructive.bg, light: l.button.destructive.bg),
      TokenSwatch(name:'button/destructive/label', description: 'Destructive label', dark: d.button.destructive.label, light: l.button.destructive.label),
    ],
  );
}

Widget buildStateUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'State',
    swatches: [
      TokenSwatch(name:'state/hover', description: 'Overlay on hover — layer over base', dark: d.state.hover, light: l.state.hover),
      TokenSwatch(name:'state/pressed', description: 'Overlay on active press', dark: d.state.pressed, light: l.state.pressed),
      TokenSwatch(name:'state/focus', description: 'Background tint on focused element', dark: d.state.focus, light: l.state.focus),
      TokenSwatch(name:'state/selected', description: 'Tint for selected row / chip', dark: d.state.selected, light: l.state.selected),
      TokenSwatch(name:'state/focus-ring', description: '2dp ring — max contrast vs page bg', dark: d.state.focusRing, light: l.state.focusRing),
      TokenSwatch(name:'state/focus-gap', description: '2dp gap between element and ring', dark: d.state.focusGap, light: l.state.focusGap),
    ],
  );
}
