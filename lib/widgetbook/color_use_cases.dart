import 'package:flutter/widgets.dart';

import '../src/core/theme/colors/app_colors.dart';
import '../src/core/theme/primitives.dart';
import 'color_swatch.dart';

// Each builder below returns a ColorCategoryPage for one Figma color sheet.
// The dark/light values are pulled straight from AppColors.dark / .light so
// the Widgetbook always mirrors the token truth — if the token file changes,
// the swatch updates automatically.

Widget buildPrimitivesNeutralUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Neutral',
    swatches: [
      TokenSwatch(
        name: '_ Primitive/0',
        description: 'Darkest anchor — ground & inverse text',
        dark: Primitives.p0Dark,
        light: Primitives.p0Light,
      ),
      TokenSwatch(
        name: '_ Primitive/50',
        description: 'Base surface dark',
        dark: Primitives.p50Dark,
        light: Primitives.p50Light,
      ),
      TokenSwatch(
        name: '_ Primitive/100',
        description: 'Raised surface dark',
        dark: Primitives.p100Dark,
        light: Primitives.p100Light,
      ),
      TokenSwatch(
        name: '_ Primitive/150',
        description: 'Overlay / accent surface',
        dark: Primitives.p150Dark,
        light: Primitives.p150Light,
      ),
      TokenSwatch(
        name: '_ Primitive/200',
        description: 'Subtle border dark',
        dark: Primitives.p200Dark,
        light: Primitives.p200Light,
      ),
      TokenSwatch(
        name: '_ Primitive/300',
        description: 'Default border dark',
        dark: Primitives.p300Dark,
        light: Primitives.p300Light,
      ),
      TokenSwatch(
        name: '_ Primitive/400',
        description: 'Strong border / disabled text',
        dark: Primitives.p400Dark,
        light: Primitives.p400Light,
      ),
      TokenSwatch(
        name: '_ Primitive/500',
        description: 'Mid-gray — same both modes',
        dark: Primitives.p500Dark,
        light: Primitives.p500Light,
      ),
      TokenSwatch(
        name: '_ Primitive/600',
        description: 'Secondary text dark',
        dark: Primitives.p600Dark,
        light: Primitives.p600Light,
      ),
      TokenSwatch(
        name: '_ Primitive/700',
        description: 'Primary text dark',
        dark: Primitives.p700Dark,
        light: Primitives.p700Light,
      ),
      TokenSwatch(
        name: '_ Primitive/800',
        description: 'Accent / primary button dark',
        dark: Primitives.p800Dark,
        light: Primitives.p800Light,
      ),
      TokenSwatch(
        name: '_ Primitive/900',
        description: 'Lightest — inverse of ground',
        dark: Primitives.p900Dark,
        light: Primitives.p900Light,
      ),
    ],
  );
}

Widget buildPrimitivesPurpleUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Purple',
    swatches: [
      TokenSwatch(
        name: '_ Primitive/Purple/0',
        description: 'Brand purple — darkest',
        dark: PurplePrimitives.p0Dark,
        light: PurplePrimitives.p0Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/50',
        description: 'Brand purple step 50',
        dark: PurplePrimitives.p50Dark,
        light: PurplePrimitives.p50Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/100',
        description: 'Brand purple step 100',
        dark: PurplePrimitives.p100Dark,
        light: PurplePrimitives.p100Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/150',
        description: 'Primary button fill (Light)',
        dark: PurplePrimitives.p150Dark,
        light: PurplePrimitives.p150Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/200',
        description: 'Light-mode brand accent',
        dark: PurplePrimitives.p200Dark,
        light: PurplePrimitives.p200Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/300',
        description: 'Primary hover (Light) / pressed (Dark)',
        dark: PurplePrimitives.p300Dark,
        light: PurplePrimitives.p300Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/400',
        description: 'Primary hover (Dark) / pressed (Light)',
        dark: PurplePrimitives.p400Dark,
        light: PurplePrimitives.p400Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/500',
        description: 'Dark-mode brand accent / primary button fill',
        dark: PurplePrimitives.p500Dark,
        light: PurplePrimitives.p500Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/600',
        description: 'Brand purple step 600',
        dark: PurplePrimitives.p600Dark,
        light: PurplePrimitives.p600Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/700',
        description: 'Brand purple step 700',
        dark: PurplePrimitives.p700Dark,
        light: PurplePrimitives.p700Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/800',
        description: 'Brand purple step 800',
        dark: PurplePrimitives.p800Dark,
        light: PurplePrimitives.p800Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Purple/900',
        description: 'Brand purple — lightest',
        dark: PurplePrimitives.p900Dark,
        light: PurplePrimitives.p900Light,
      ),
    ],
  );
}

Widget buildPrimitivesCyanUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Cyan',
    swatches: [
      TokenSwatch(
        name: '_ Primitive/Cyan/0',
        description: 'Brand cyan — darkest',
        dark: CyanPrimitives.p0Dark,
        light: CyanPrimitives.p0Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/50',
        description: 'Brand cyan step 50',
        dark: CyanPrimitives.p50Dark,
        light: CyanPrimitives.p50Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/100',
        description: 'Brand cyan step 100',
        dark: CyanPrimitives.p100Dark,
        light: CyanPrimitives.p100Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/150',
        description: 'icon/brand-cyan (Light)',
        dark: CyanPrimitives.p150Dark,
        light: CyanPrimitives.p150Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/200',
        description: 'Brand cyan step 200',
        dark: CyanPrimitives.p200Dark,
        light: CyanPrimitives.p200Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/300',
        description: 'Brand cyan step 300',
        dark: CyanPrimitives.p300Dark,
        light: CyanPrimitives.p300Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/400',
        description: 'text/brand-cyan (Light)',
        dark: CyanPrimitives.p400Dark,
        light: CyanPrimitives.p400Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/500',
        description: 'icon/brand-cyan (Dark)',
        dark: CyanPrimitives.p500Dark,
        light: CyanPrimitives.p500Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/600',
        description: 'text/brand-cyan (Dark)',
        dark: CyanPrimitives.p600Dark,
        light: CyanPrimitives.p600Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/700',
        description: 'Brand cyan step 700',
        dark: CyanPrimitives.p700Dark,
        light: CyanPrimitives.p700Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/800',
        description: 'Brand cyan step 800',
        dark: CyanPrimitives.p800Dark,
        light: CyanPrimitives.p800Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Cyan/900',
        description: 'Brand cyan — lightest',
        dark: CyanPrimitives.p900Dark,
        light: CyanPrimitives.p900Light,
      ),
    ],
  );
}

Widget buildPrimitivesYellowUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Yellow',
    swatches: [
      TokenSwatch(
        name: '_ Primitive/Yellow/0',
        description: 'Brand yellow — darkest',
        dark: YellowPrimitives.p0Dark,
        light: YellowPrimitives.p0Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/50',
        description: 'Brand yellow step 50',
        dark: YellowPrimitives.p50Dark,
        light: YellowPrimitives.p50Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/100',
        description: 'Brand yellow step 100',
        dark: YellowPrimitives.p100Dark,
        light: YellowPrimitives.p100Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/150',
        description: 'Brand yellow step 150',
        dark: YellowPrimitives.p150Dark,
        light: YellowPrimitives.p150Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/200',
        description: 'Brand yellow step 200',
        dark: YellowPrimitives.p200Dark,
        light: YellowPrimitives.p200Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/300',
        description: 'text/icon warning (Light)',
        dark: YellowPrimitives.p300Dark,
        light: YellowPrimitives.p300Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/400',
        description: 'text/icon warning (Dark)',
        dark: YellowPrimitives.p400Dark,
        light: YellowPrimitives.p400Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/500',
        description: 'Brand yellow step 500',
        dark: YellowPrimitives.p500Dark,
        light: YellowPrimitives.p500Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/600',
        description: 'Brand yellow step 600',
        dark: YellowPrimitives.p600Dark,
        light: YellowPrimitives.p600Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/700',
        description: 'Brand yellow step 700',
        dark: YellowPrimitives.p700Dark,
        light: YellowPrimitives.p700Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/800',
        description: 'Brand yellow step 800',
        dark: YellowPrimitives.p800Dark,
        light: YellowPrimitives.p800Light,
      ),
      TokenSwatch(
        name: '_ Primitive/Yellow/900',
        description: 'Brand yellow — lightest',
        dark: YellowPrimitives.p900Dark,
        light: YellowPrimitives.p900Light,
      ),
    ],
  );
}

Widget buildBackgroundUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Background',
    swatches: [
      TokenSwatch(
        name: 'bg/ground',
        description: 'Deepest layer — Scaffold background',
        dark: d.background.ground,
        light: l.background.ground,
      ),
      TokenSwatch(
        name: 'bg/base',
        description: 'Primary content surface, main panels',
        dark: d.background.base,
        light: l.background.base,
      ),
      TokenSwatch(
        name: 'bg/raised',
        description: 'Cards, modals, sidebars, drawers',
        dark: d.background.raised,
        light: l.background.raised,
      ),
      TokenSwatch(
        name: 'bg/overlay',
        description: 'Dropdowns, popovers, floating elements',
        dark: d.background.overlay,
        light: l.background.overlay,
      ),
      TokenSwatch(
        name: 'bg/brand-cyan-subtle',
        description: 'Brand-cyan tinted surface — info panels',
        dark: d.background.brandCyanSubtle,
        light: l.background.brandCyanSubtle,
      ),
      TokenSwatch(
        name: 'bg/brand-cyan-strong',
        description: 'Brand-cyan emphasis surface',
        dark: d.background.brandCyanStrong,
        light: l.background.brandCyanStrong,
      ),
    ],
  );
}

Widget buildSurfaceUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Surface',
    swatches: [
      TokenSwatch(
        name: 'surface/card',
        description: 'Card components, list rows',
        dark: d.surface.card,
        light: l.surface.card,
      ),
      TokenSwatch(
        name: 'surface/input',
        description: 'Text input background at rest',
        dark: d.surface.input,
        light: l.surface.input,
      ),
      TokenSwatch(
        name: 'surface/input-focus',
        description: 'Text input when focused',
        dark: d.surface.inputFocus,
        light: l.surface.inputFocus,
      ),
      TokenSwatch(
        name: 'surface/nav',
        description: 'Navigation rail background',
        dark: d.surface.nav,
        light: l.surface.nav,
      ),
      TokenSwatch(
        name: 'surface/nav-active',
        description: 'Active nav item indicator',
        dark: d.surface.navActive,
        light: l.surface.navActive,
      ),
      TokenSwatch(
        name: 'surface/tooltip',
        description: 'Tooltip / popover background',
        dark: d.surface.tooltip,
        light: l.surface.tooltip,
      ),
    ],
  );
}

Widget buildBorderUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Border',
    swatches: [
      TokenSwatch(
        name: 'border/subtle',
        description: 'Hairline dividers, row separators',
        dark: d.border.subtle,
        light: l.border.subtle,
      ),
      TokenSwatch(
        name: 'border/regular',
        description: 'Input fields, cards, chips',
        dark: d.border.regular,
        light: l.border.regular,
      ),
      TokenSwatch(
        name: 'border/strong',
        description: 'Selected states, active tabs',
        dark: d.border.strong,
        light: l.border.strong,
      ),
      TokenSwatch(
        name: 'border/utility/destructive',
        description: 'Validation and destructive emphasis',
        dark: d.border.utilityDestructive,
        light: l.border.utilityDestructive,
      ),
      TokenSwatch(
        name: 'border/brand-cyan-subtle',
        description: 'Brand-cyan border for subtle info surfaces',
        dark: d.border.brandCyanSubtle,
        light: l.border.brandCyanSubtle,
      ),
      TokenSwatch(
        name: 'border/brand-cyan-strong',
        description: 'Brand-cyan border for emphasis',
        dark: d.border.brandCyanStrong,
        light: l.border.brandCyanStrong,
      ),
      TokenSwatch(
        name: 'border/brand-purple-strong',
        description: 'Brand-purple border for affirmative feedback',
        dark: d.border.brandPurpleStrong,
        light: l.border.brandPurpleStrong,
      ),
    ],
  );
}

Widget buildTextUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Text',
    swatches: [
      TokenSwatch(
        name: 'text/accent',
        description: 'Titles, headings, max contrast',
        dark: d.text.accent,
        light: l.text.accent,
      ),
      TokenSwatch(
        name: 'text/primary',
        description: 'Default body text, paragraphs',
        dark: d.text.primary,
        light: l.text.primary,
      ),
      TokenSwatch(
        name: 'text/secondary',
        description: 'Subtitles, timestamps, metadata',
        dark: d.text.secondary,
        light: l.text.secondary,
      ),
      TokenSwatch(
        name: 'text/muted',
        description: 'Descriptions — same both modes',
        dark: d.text.muted,
        light: l.text.muted,
      ),
      TokenSwatch(
        name: 'text/disabled',
        description: 'Inactive, unavailable labels',
        dark: d.text.disabled,
        light: l.text.disabled,
      ),
      TokenSwatch(
        name: 'text/inverse',
        description: 'Text on inverted surfaces',
        dark: d.text.inverse,
        light: l.text.inverse,
      ),
      TokenSwatch(
        name: 'text/warning',
        description: 'Inline warning copy — brand yellow',
        dark: d.text.warning,
        light: l.text.warning,
      ),
      TokenSwatch(
        name: 'text/brand-purple',
        description: 'Brand-purple inline text accent',
        dark: d.text.brandPurple,
        light: l.text.brandPurple,
      ),
      TokenSwatch(
        name: 'text/brand-cyan',
        description: 'Brand-cyan inline text accent',
        dark: d.text.brandCyan,
        light: l.text.brandCyan,
      ),
    ],
  );
}

Widget buildIconUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Icon',
    swatches: [
      TokenSwatch(
        name: 'icon/accent',
        description: 'Active, selected, primary icons',
        dark: d.icon.accent,
        light: l.icon.accent,
      ),
      TokenSwatch(
        name: 'icon/regular',
        description: 'Standard UI icons',
        dark: d.icon.regular,
        light: l.icon.regular,
      ),
      TokenSwatch(
        name: 'icon/muted',
        description: 'Inactive, decorative icons',
        dark: d.icon.muted,
        light: l.icon.muted,
      ),
      TokenSwatch(
        name: 'icon/disabled',
        description: 'Disabled control icons',
        dark: d.icon.disabled,
        light: l.icon.disabled,
      ),
      TokenSwatch(
        name: 'icon/inverse',
        description: 'Icons on inverted surfaces',
        dark: d.icon.inverse,
        light: l.icon.inverse,
      ),
      TokenSwatch(
        name: 'icon/on-primary',
        description: 'Icons inside primary button',
        dark: d.icon.onPrimary,
        light: l.icon.onPrimary,
      ),
      TokenSwatch(
        name: 'icon/warning',
        description: 'Warning-state icon — brand yellow',
        dark: d.icon.warning,
        light: l.icon.warning,
      ),
      TokenSwatch(
        name: 'icon/brand-purple',
        description: 'Brand-purple icon',
        dark: d.icon.brandPurple,
        light: l.icon.brandPurple,
      ),
      TokenSwatch(
        name: 'icon/brand-cyan',
        description: 'Brand-cyan icon',
        dark: d.icon.brandCyan,
        light: l.icon.brandCyan,
      ),
    ],
  );
}

Widget buildButtonPrimaryUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Button / Primary',
    swatches: [
      TokenSwatch(
        name: 'button/primary/bg',
        description: 'Fill at rest',
        dark: d.button.primary.bg,
        light: l.button.primary.bg,
      ),
      TokenSwatch(
        name: 'button/primary/bg-hover',
        description: 'Fill on hover',
        dark: d.button.primary.bgHover,
        light: l.button.primary.bgHover,
      ),
      TokenSwatch(
        name: 'button/primary/bg-pressed',
        description: 'Fill on press',
        dark: d.button.primary.bgPressed,
        light: l.button.primary.bgPressed,
      ),
      TokenSwatch(
        name: 'button/primary/border',
        description: 'Subtle alpha border',
        dark: d.button.primary.border,
        light: l.button.primary.border,
      ),
      TokenSwatch(
        name: 'button/primary/label',
        description: 'Label inside primary button',
        dark: d.button.primary.label,
        light: l.button.primary.label,
      ),
    ],
  );
}

Widget buildButtonSecondaryUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Button / Secondary',
    swatches: [
      TokenSwatch(
        name: 'button/secondary/bg',
        description: 'Fill at rest',
        dark: d.button.secondary.bg,
        light: l.button.secondary.bg,
      ),
      TokenSwatch(
        name: 'button/secondary/bg-hover',
        description: 'Fill on hover',
        dark: d.button.secondary.bgHover,
        light: l.button.secondary.bgHover,
      ),
      TokenSwatch(
        name: 'button/secondary/bg-pressed',
        description: 'Fill on press',
        dark: d.button.secondary.bgPressed,
        light: l.button.secondary.bgPressed,
      ),
      TokenSwatch(
        name: 'button/secondary/label',
        description: 'Label inside secondary button',
        dark: d.button.secondary.label,
        light: l.button.secondary.label,
      ),
    ],
  );
}

Widget buildButtonGhostDestructiveUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Button / Ghost & Destructive',
    swatches: [
      TokenSwatch(
        name: 'button/ghost/bg',
        description: 'Transparent base',
        dark: d.button.ghost.bg,
        light: l.button.ghost.bg,
      ),
      TokenSwatch(
        name: 'button/ghost/bg-hover',
        description: 'Tint on hover',
        dark: d.button.ghost.bgHover,
        light: l.button.ghost.bgHover,
      ),
      TokenSwatch(
        name: 'button/ghost/border',
        description: 'Ghost border (primary affordance)',
        dark: d.button.ghost.border,
        light: l.button.ghost.border,
      ),
      TokenSwatch(
        name: 'button/ghost/label',
        description: 'Ghost label',
        dark: d.button.ghost.label,
        light: l.button.ghost.label,
      ),
      TokenSwatch(
        name: 'button/destructive/bg',
        description: 'Destructive fill (delete, wipe)',
        dark: d.button.destructive.bg,
        light: l.button.destructive.bg,
      ),
      TokenSwatch(
        name: 'button/destructive/bg-hover',
        description: 'Destructive fill on hover',
        dark: d.button.destructive.bgHover,
        light: l.button.destructive.bgHover,
      ),
      TokenSwatch(
        name: 'button/destructive/bg-pressed',
        description: 'Destructive fill on press',
        dark: d.button.destructive.bgPressed,
        light: l.button.destructive.bgPressed,
      ),
      TokenSwatch(
        name: 'button/destructive/border',
        description: 'Destructive alpha border',
        dark: d.button.destructive.border,
        light: l.button.destructive.border,
      ),
      TokenSwatch(
        name: 'button/destructive/label',
        description: 'Destructive label',
        dark: d.button.destructive.label,
        light: l.button.destructive.label,
      ),
    ],
  );
}

Widget buildStateUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'State',
    swatches: [
      TokenSwatch(
        name: 'state/hover',
        description: 'Overlay on hover — layer over base',
        dark: d.state.hover,
        light: l.state.hover,
      ),
      TokenSwatch(
        name: 'state/pressed',
        description: 'Overlay on active press',
        dark: d.state.pressed,
        light: l.state.pressed,
      ),
      TokenSwatch(
        name: 'state/focus',
        description: 'Background tint on focused element',
        dark: d.state.focus,
        light: l.state.focus,
      ),
      TokenSwatch(
        name: 'state/selected',
        description: 'Tint for selected row / chip',
        dark: d.state.selected,
        light: l.state.selected,
      ),
      TokenSwatch(
        name: 'state/focus-ring',
        description: '2dp ring — max contrast vs page bg',
        dark: d.state.focusRing,
        light: l.state.focusRing,
      ),
      TokenSwatch(
        name: 'state/focus-gap',
        description: '2dp gap between element and ring',
        dark: d.state.focusGap,
        light: l.state.focusGap,
      ),
      TokenSwatch(
        name: 'state/focus-ring-brand',
        description: 'Brand-cyan ring for primary button focus',
        dark: d.state.focusRingBrand,
        light: l.state.focusRingBrand,
      ),
      TokenSwatch(
        name: 'state/focus-ring-destructive',
        description: 'Destructive ring for destructive button focus',
        dark: d.state.focusRingDestructive,
        light: l.state.focusRingDestructive,
      ),
    ],
  );
}

Widget buildFadeUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Fade',
    swatches: [
      TokenSwatch(
        name: 'fade/illustration',
        description:
            'Scrim for bottom-anchored art — dark=50% over p0, light=transparent',
        dark: d.fade.illustration,
        light: l.fade.illustration,
      ),
    ],
  );
}
