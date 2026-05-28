import 'package:flutter/widgets.dart';

import '../src/core/theme/colors/app_colors.dart';
import '../src/core/theme/primitives.dart';
import 'color_swatch.dart';

// Each builder below returns a ColorCategoryPage for one Figma color sheet.
// The dark/light values are pulled straight from AppColors.dark / .light so
// the Widgetbook always mirrors the token truth — if the token file changes,
// the swatch updates automatically.

List<TokenSwatch> _primitiveScaleSwatches({
  required String prefix,
  required List<Color> dark,
  required List<Color> light,
}) {
  const steps = [
    '0',
    '50',
    '100',
    '150',
    '200',
    '300',
    '400',
    '500',
    '600',
    '700',
    '800',
    '900',
  ];
  return [
    for (var i = 0; i < steps.length; i++)
      TokenSwatch(
        name: '$prefix/${steps[i]}',
        description: '$prefix step ${steps[i]}',
        dark: dark[i],
        light: light[i],
      ),
  ];
}

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

Widget buildPrimitivesCrimsonUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Crimson',
    swatches: _primitiveScaleSwatches(
      prefix: '_ Primitive/Crimson',
      dark: const [
        CrimsonPrimitives.p0Dark,
        CrimsonPrimitives.p50Dark,
        CrimsonPrimitives.p100Dark,
        CrimsonPrimitives.p150Dark,
        CrimsonPrimitives.p200Dark,
        CrimsonPrimitives.p300Dark,
        CrimsonPrimitives.p400Dark,
        CrimsonPrimitives.p500Dark,
        CrimsonPrimitives.p600Dark,
        CrimsonPrimitives.p700Dark,
        CrimsonPrimitives.p800Dark,
        CrimsonPrimitives.p900Dark,
      ],
      light: const [
        CrimsonPrimitives.p0Light,
        CrimsonPrimitives.p50Light,
        CrimsonPrimitives.p100Light,
        CrimsonPrimitives.p150Light,
        CrimsonPrimitives.p200Light,
        CrimsonPrimitives.p300Light,
        CrimsonPrimitives.p400Light,
        CrimsonPrimitives.p500Light,
        CrimsonPrimitives.p600Light,
        CrimsonPrimitives.p700Light,
        CrimsonPrimitives.p800Light,
        CrimsonPrimitives.p900Light,
      ],
    ),
  );
}

Widget buildPrimitivesPlumUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Plum',
    swatches: _primitiveScaleSwatches(
      prefix: '_ Primitive/Plum',
      dark: const [
        PlumPrimitives.p0Dark,
        PlumPrimitives.p50Dark,
        PlumPrimitives.p100Dark,
        PlumPrimitives.p150Dark,
        PlumPrimitives.p200Dark,
        PlumPrimitives.p300Dark,
        PlumPrimitives.p400Dark,
        PlumPrimitives.p500Dark,
        PlumPrimitives.p600Dark,
        PlumPrimitives.p700Dark,
        PlumPrimitives.p800Dark,
        PlumPrimitives.p900Dark,
      ],
      light: const [
        PlumPrimitives.p0Light,
        PlumPrimitives.p50Light,
        PlumPrimitives.p100Light,
        PlumPrimitives.p150Light,
        PlumPrimitives.p200Light,
        PlumPrimitives.p300Light,
        PlumPrimitives.p400Light,
        PlumPrimitives.p500Light,
        PlumPrimitives.p600Light,
        PlumPrimitives.p700Light,
        PlumPrimitives.p800Light,
        PlumPrimitives.p900Light,
      ],
    ),
  );
}

Widget buildPrimitivesGoldUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Gold',
    swatches: _primitiveScaleSwatches(
      prefix: '_ Primitive/Gold',
      dark: const [
        GoldPrimitives.p0Dark,
        GoldPrimitives.p50Dark,
        GoldPrimitives.p100Dark,
        GoldPrimitives.p150Dark,
        GoldPrimitives.p200Dark,
        GoldPrimitives.p300Dark,
        GoldPrimitives.p400Dark,
        GoldPrimitives.p500Dark,
        GoldPrimitives.p600Dark,
        GoldPrimitives.p700Dark,
        GoldPrimitives.p800Dark,
        GoldPrimitives.p900Dark,
      ],
      light: const [
        GoldPrimitives.p0Light,
        GoldPrimitives.p50Light,
        GoldPrimitives.p100Light,
        GoldPrimitives.p150Light,
        GoldPrimitives.p200Light,
        GoldPrimitives.p300Light,
        GoldPrimitives.p400Light,
        GoldPrimitives.p500Light,
        GoldPrimitives.p600Light,
        GoldPrimitives.p700Light,
        GoldPrimitives.p800Light,
        GoldPrimitives.p900Light,
      ],
    ),
  );
}

Widget buildPrimitivesGreenUseCase(BuildContext context) {
  return ColorCategoryPage(
    title: 'Primitives / Green',
    swatches: _primitiveScaleSwatches(
      prefix: '_ Primitive/Green',
      dark: const [
        GreenPrimitives.p0Dark,
        GreenPrimitives.p50Dark,
        GreenPrimitives.p100Dark,
        GreenPrimitives.p150Dark,
        GreenPrimitives.p200Dark,
        GreenPrimitives.p300Dark,
        GreenPrimitives.p400Dark,
        GreenPrimitives.p500Dark,
        GreenPrimitives.p600Dark,
        GreenPrimitives.p700Dark,
        GreenPrimitives.p800Dark,
        GreenPrimitives.p900Dark,
      ],
      light: const [
        GreenPrimitives.p0Light,
        GreenPrimitives.p50Light,
        GreenPrimitives.p100Light,
        GreenPrimitives.p150Light,
        GreenPrimitives.p200Light,
        GreenPrimitives.p300Light,
        GreenPrimitives.p400Light,
        GreenPrimitives.p500Light,
        GreenPrimitives.p600Light,
        GreenPrimitives.p700Light,
        GreenPrimitives.p800Light,
        GreenPrimitives.p900Light,
      ],
    ),
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
        name: 'bg/inverse',
        description: 'Inverted neutral background',
        dark: d.background.inverse,
        light: l.background.inverse,
      ),
      TokenSwatch(
        name: 'bg/neutral/alpha/scrim',
        description: 'Neutral alpha scrim',
        dark: d.background.neutralScrim,
        light: l.background.neutralScrim,
      ),
      TokenSwatch(
        name: 'bg/neutral/alpha/subtle-opacity',
        description: 'Subtle neutral alpha overlay',
        dark: d.background.neutralSubtleOpacity,
        light: l.background.neutralSubtleOpacity,
      ),
      TokenSwatch(
        name: 'bg/neutral/alpha/strong-opacity',
        description: 'Strong neutral alpha overlay',
        dark: d.background.neutralStrongOpacity,
        light: l.background.neutralStrongOpacity,
      ),
      TokenSwatch(
        name: 'bg/brand/crimson-subtle',
        description: 'Brand-crimson tinted surface',
        dark: d.background.brandCrimsonSubtle,
        light: l.background.brandCrimsonSubtle,
      ),
      TokenSwatch(
        name: 'bg/brand/crimson-strong',
        description: 'Brand-crimson emphasis surface',
        dark: d.background.brandCrimsonStrong,
        light: l.background.brandCrimsonStrong,
      ),
      TokenSwatch(
        name: 'bg/brand/alpha/crimson-alpha',
        description: 'Brand-crimson alpha overlay',
        dark: d.background.brandCrimsonAlpha,
        light: l.background.brandCrimsonAlpha,
      ),
      TokenSwatch(
        name: 'bg/utility/destructive-subtle',
        description: 'Destructive utility surface',
        dark: d.background.utilityDestructiveSubtle,
        light: l.background.utilityDestructiveSubtle,
      ),
      TokenSwatch(
        name: 'bg/utility/alpha/destructive-alpha-subtle',
        description: 'Subtle destructive utility alpha overlay',
        dark: d.background.utilityDestructiveAlphaSubtle,
        light: l.background.utilityDestructiveAlphaSubtle,
      ),
      TokenSwatch(
        name: 'bg/utility/alpha/destructive-alpha',
        description: 'Destructive utility alpha overlay',
        dark: d.background.utilityDestructiveAlpha,
        light: l.background.utilityDestructiveAlpha,
      ),
      TokenSwatch(
        name: 'bg/utility/success-subtle',
        description: 'Success utility surface',
        dark: d.background.utilitySuccessSubtle,
        light: l.background.utilitySuccessSubtle,
      ),
      TokenSwatch(
        name: 'bg/utility/success-strong',
        description: 'Strong success utility surface',
        dark: d.background.utilitySuccessStrong,
        light: l.background.utilitySuccessStrong,
      ),
      TokenSwatch(
        name: 'bg/utility/alpha/success-alpha',
        description: 'Success utility alpha overlay',
        dark: d.background.utilitySuccessAlpha,
        light: l.background.utilitySuccessAlpha,
      ),
      TokenSwatch(
        name: 'bg/exceptions/home-card',
        description: 'Exception surface for the home balance card',
        dark: d.background.homeCard,
        light: l.background.homeCard,
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
        name: 'border/neutral/alpha/subtle-opacity',
        description: 'Alpha border used on strong filled controls',
        dark: d.border.subtleOpacity,
        light: l.border.subtleOpacity,
      ),
      TokenSwatch(
        name: 'border/neutral/alpha/inverse-opacity',
        description: 'Alpha border over inverted / strong fills',
        dark: d.border.inverseOpacity,
        light: l.border.inverseOpacity,
      ),
      TokenSwatch(
        name: 'border/default',
        description: 'Default border for hover / cards / chips',
        dark: d.border.regular,
        light: l.border.regular,
      ),
      TokenSwatch(
        name: 'border/medium',
        description: 'Active / filled input fields',
        dark: d.border.medium,
        light: l.border.medium,
      ),
      TokenSwatch(
        name: 'border/strong',
        description: 'Max-contrast border',
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
        name: 'border/utility/destructive-subtle',
        description: 'Soft destructive border',
        dark: d.border.utilityDestructiveSubtle,
        light: l.border.utilityDestructiveSubtle,
      ),
      TokenSwatch(
        name: 'border/utility/success',
        description: 'Success utility border',
        dark: d.border.utilitySuccess,
        light: l.border.utilitySuccess,
      ),
      TokenSwatch(
        name: 'border/brand/crimson-strong',
        description: 'Brand-crimson border for feedback',
        dark: d.border.brandCrimsonStrong,
        light: l.border.brandCrimsonStrong,
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
        description: 'Legacy warning copy — gold utility',
        dark: d.text.warning,
        light: l.text.warning,
      ),
      TokenSwatch(
        name: 'text/positive/strong',
        description: 'Positive-state copy — green utility',
        dark: d.text.positiveStrong,
        light: l.text.positiveStrong,
      ),
      TokenSwatch(
        name: 'text/utility/destructive',
        description: 'Destructive utility copy',
        dark: d.text.destructive,
        light: l.text.destructive,
      ),
      TokenSwatch(
        name: 'text/utility/destructive-light',
        description: 'Secondary destructive utility copy',
        dark: d.text.destructiveLight,
        light: l.text.destructiveLight,
      ),
      TokenSwatch(
        name: 'text/utility/success',
        description: 'Success utility copy',
        dark: d.text.success,
        light: l.text.success,
      ),
      TokenSwatch(
        name: 'text/brand/crimson',
        description: 'Brand-crimson inline text accent',
        dark: d.text.brandCrimson,
        light: l.text.brandCrimson,
      ),
      TokenSwatch(
        name: 'text/exception/home-card-text',
        description: 'Exception text used on the home balance card',
        dark: d.text.homeCard,
        light: l.text.homeCard,
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
        description: 'Legacy warning icon — gold utility',
        dark: d.icon.warning,
        light: l.icon.warning,
      ),
      TokenSwatch(
        name: 'icon/utility/destructive',
        description: 'Destructive utility icon',
        dark: d.icon.destructive,
        light: l.icon.destructive,
      ),
      TokenSwatch(
        name: 'icon/utility/destructive-light',
        description: 'Secondary destructive utility icon',
        dark: d.icon.destructiveLight,
        light: l.icon.destructiveLight,
      ),
      TokenSwatch(
        name: 'icon/utility/success',
        description: 'Success utility icon',
        dark: d.icon.success,
        light: l.icon.success,
      ),
      TokenSwatch(
        name: 'icon/brand/crimson',
        description: 'Brand-crimson icon',
        dark: d.icon.brandCrimson,
        light: l.icon.brandCrimson,
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
        description: 'Border at rest',
        dark: d.button.primary.border,
        light: l.button.primary.border,
      ),
      TokenSwatch(
        name: 'button/primary/border-hover',
        description: 'Border on hover',
        dark: d.button.primary.borderHover,
        light: l.button.primary.borderHover,
      ),
      TokenSwatch(
        name: 'button/primary/border-pressed',
        description: 'Border on press',
        dark: d.button.primary.borderPressed,
        light: l.button.primary.borderPressed,
      ),
      TokenSwatch(
        name: 'button/primary/label',
        description: 'Label inside primary button',
        dark: d.button.primary.label,
        light: l.button.primary.label,
      ),
      TokenSwatch(
        name: 'button/primary/label-hover',
        description: 'Label inside primary button on hover',
        dark: d.button.primary.labelHover,
        light: l.button.primary.labelHover,
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
        description: 'Destructive alpha border at rest',
        dark: d.button.destructive.border,
        light: l.button.destructive.border,
      ),
      TokenSwatch(
        name: 'button/destructive/border-hover',
        description: 'Destructive alpha border on hover',
        dark: d.button.destructive.borderHover,
        light: l.button.destructive.borderHover,
      ),
      TokenSwatch(
        name: 'button/destructive/border-pressed',
        description: 'Destructive alpha border on press',
        dark: d.button.destructive.borderPressed,
        light: l.button.destructive.borderPressed,
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
        name: 'state/neutral/alpha/selected-opacity',
        description: 'Alpha overlay for selected row / chip',
        dark: d.state.selectedOpacity,
        light: l.state.selectedOpacity,
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
        description: 'Brand-crimson ring for primary button focus',
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

Widget buildNavPanelUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Nav Panel',
    swatches: [
      TokenSwatch(
        name: 'nav-panel/badge/bg',
        description: 'Badge fill',
        dark: d.navPanel.badgeBg,
        light: l.navPanel.badgeBg,
      ),
      TokenSwatch(
        name: 'nav-panel/badge/label',
        description: 'Badge label',
        dark: d.navPanel.badgeLabel,
        light: l.navPanel.badgeLabel,
      ),
      TokenSwatch(
        name: 'nav-panel/active/bg',
        description: 'Active navigation item background',
        dark: d.navPanel.activeBg,
        light: l.navPanel.activeBg,
      ),
      TokenSwatch(
        name: 'nav-panel/active/icon',
        description: 'Active navigation item icon',
        dark: d.navPanel.activeIcon,
        light: l.navPanel.activeIcon,
      ),
      TokenSwatch(
        name: 'nav-panel/active/label',
        description: 'Active navigation item label',
        dark: d.navPanel.activeLabel,
        light: l.navPanel.activeLabel,
      ),
      TokenSwatch(
        name: 'nav-panel/hover/bg',
        description: 'Navigation item hover background',
        dark: d.navPanel.hoverBg,
        light: l.navPanel.hoverBg,
      ),
    ],
  );
}

Widget buildShadowsUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Shadows',
    swatches: [
      TokenSwatch(
        name: 'shadows/subtle',
        description: 'Subtle shadow overlay',
        dark: d.shadows.subtle,
        light: l.shadows.subtle,
      ),
      TokenSwatch(
        name: 'shadows/default',
        description: 'Default shadow overlay',
        dark: d.shadows.regular,
        light: l.shadows.regular,
      ),
    ],
  );
}

Widget buildSyncUseCase(BuildContext context) {
  const d = AppColors.dark;
  const l = AppColors.light;
  return ColorCategoryPage(
    title: 'Sync',
    swatches: [
      TokenSwatch(
        name: 'sync/text',
        description: 'Synced state text',
        dark: d.sync.text,
        light: l.sync.text,
      ),
      TokenSwatch(
        name: 'sync/text-syncing',
        description: 'Syncing state text',
        dark: d.sync.textSyncing,
        light: l.sync.textSyncing,
      ),
      TokenSwatch(
        name: 'sync/text-error',
        description: 'Error state text',
        dark: d.sync.textError,
        light: l.sync.textError,
      ),
      TokenSwatch(
        name: 'sync/light-success',
        description: 'Success indicator light',
        dark: d.sync.lightSuccess,
        light: l.sync.lightSuccess,
      ),
      TokenSwatch(
        name: 'sync/light-error',
        description: 'Error indicator light',
        dark: d.sync.lightError,
        light: l.sync.lightError,
      ),
    ],
  );
}
