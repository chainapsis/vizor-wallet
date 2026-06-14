import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_icon_size.dart';
import 'package:zcash_wallet/src/core/theme/app_radii.dart';
import 'package:zcash_wallet/src/core/theme/app_sizing.dart';
import 'package:zcash_wallet/src/core/theme/app_spacing.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_data.dart';
import 'package:zcash_wallet/src/core/theme/app_typography.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';

void main() {
  test('token selectors resolve to the compiled form factor set', () {
    // `flutter test` runs with the default define (desktop) unless a
    // --dart-define=VIZOR_FORM_FACTOR=mobile lane overrides it; this test
    // is form-factor agnostic so it passes in both lanes.
    final mobile = kAppFormFactor == AppFormFactor.mobile;

    expect(
      AppTypography.bodyMedium,
      mobile ? AppTypographyMobile.bodyMedium : AppTypographyDesktop.bodyMedium,
    );
    expect(
      AppTypography.displayLarge,
      mobile
          ? AppTypographyMobile.displayLarge
          : AppTypographyDesktop.displayLarge,
    );
    expect(
      AppTypography.headlineMedium,
      mobile
          ? AppTypographyMobile.headlineMedium
          : AppTypographyDesktop.headlineMedium,
    );
    expect(
      AppTypography.codeMedium,
      mobile ? AppTypographyMobile.codeMedium : AppTypographyDesktop.codeMedium,
    );
    expect(
      AppButtonSizing.largeHeight,
      mobile
          ? AppButtonSizingMobile.largeHeight
          : AppButtonSizingDesktop.largeHeight,
    );
    expect(
      AppInputSizing.height,
      mobile ? AppInputSizingMobile.height : AppInputSizingDesktop.height,
    );
    expect(
      AppAssetSize.size,
      mobile ? AppAssetSizeMobile.size : AppAssetSizeDesktop.size,
    );
    expect(
      AppButtonSizing.mediumSmallIconSize,
      mobile
          ? AppButtonSizingMobile.mediumSmallIconSize
          : AppButtonSizingDesktop.mediumSmallIconSize,
    );
  });

  test('desktop sizing tokens match 1 Sizing-3.zip', () {
    expect(AppSpacing.xxs, 4);
    expect(AppSpacing.xs, 8);
    expect(AppSpacing.s, 12);
    expect(AppSpacing.sm, 16);
    expect(AppSpacing.md, 24);
    expect(AppSpacing.base, 32);
    expect(AppSpacing.lg, 48);
    expect(AppSpacing.xl, 64);
    expect(AppSpacing.xl2, 96);
    expect(AppSpacing.xl3, 128);

    expect(AppRadii.xSmall, 8);
    expect(AppRadii.small, 12);
    expect(AppRadii.medium, 16);
    expect(AppRadii.large, 24);
    expect(AppRadii.xLarge, 32);
    expect(AppRadii.full, 999);

    expect(AppAssetSizeDesktop.size, 32);
    expect(AppAssetSizeDesktop.icon, 16);
    expect(AppAssetSizeDesktop.padding, 4);
    expect(AppIconSize.medium, AppAssetSizeDesktop.icon);

    expect(AppButtonSizingDesktop.largeHeight, 44);
    expect(AppButtonSizingDesktop.mediumSmallIconSize, 16);

    expect(AppInputSizingDesktop.height, 46);
    expect(AppInputSizingDesktop.iconWrapWidth, 32);
    expect(AppInputSizingDesktop.iconSize, 20);
    expect(AppInputSizingDesktop.radius, AppRadii.small);

    expect(AppWindowSizing.minWidth, 1080);
    expect(AppWindowSizing.minHeight, 720);
    expect(AppWindowSizing.maxWidth, 1296);
    expect(AppWindowSizing.maxHeight, 864);
    expect(AppWindowSizing.contentAreaMaxWidth, 420);
    expect(AppWindowSizing.paneRadius, 20);
  });

  test('mobile sizing tokens match 1 Sizing-3.zip', () {
    expect(AppAssetSizeMobile.size, 40);
    expect(AppAssetSizeMobile.icon, 18);
    expect(AppAssetSizeMobile.padding, 0);

    expect(AppButtonSizingMobile.largeHeight, 50);
    expect(AppButtonSizingMobile.mediumSmallIconSize, 20);

    expect(AppInputSizingMobile.height, 60);
    expect(AppInputSizingMobile.iconWrapWidth, 36);
    expect(AppInputSizingMobile.iconSize, 24);
    // Figma `Input/Radii` aliases `Radii.SM` (16) on mobile; the Figma
    // radii scale is shifted one tier against Dart's, so `SM` = `medium`.
    expect(AppInputSizingMobile.radius, AppRadii.medium);
  });

  test('desktop font tokens match 3 Fonts-3.zip', () {
    expect(AppTypographyDesktop.displayMedium.fontFamily, 'Libre Caslon Text');
    expect(AppTypographyDesktop.displayMedium.fontWeight, FontWeight.w400);
    expect(AppTypographyDesktop.displayMedium.fontSize, 45);
    expect(AppTypographyDesktop.displayMedium.height, 48 / 45);
    expect(AppTypographyDesktop.displayMedium.letterSpacing, -1.35);

    expect(AppTypographyDesktop.headlineLarge.fontFamily, 'Libre Caslon Text');
    expect(AppTypographyDesktop.headlineLarge.fontWeight, FontWeight.w400);
    expect(AppTypographyDesktop.headlineLarge.fontSize, 32);
    expect(AppTypographyDesktop.headlineLarge.height, 33 / 32);

    expect(AppTypographyDesktop.headlineMedium.fontFamily, 'Libre Caslon Text');
    expect(AppTypographyDesktop.headlineMedium.fontWeight, FontWeight.w400);
    expect(AppTypographyDesktop.headlineMedium.fontSize, 28);
    expect(AppTypographyDesktop.headlineMedium.height, 30 / 28);
    expect(AppTypographyDesktop.headlineMedium.letterSpacing, -0.28);

    expect(AppTypographyDesktop.headlineSmall.fontSize, 16);
    expect(AppTypographyDesktop.headlineSmall.height, 20 / 16);

    expect(AppTypographyDesktop.bodyLarge.fontSize, 16);
    expect(AppTypographyDesktop.bodyLarge.height, 24 / 16);
    expect(AppTypographyDesktop.bodyMedium.fontSize, 14);
    expect(AppTypographyDesktop.bodyMedium.height, 21 / 14);
    expect(AppTypographyDesktop.bodyMediumStrong.fontSize, 14);
    expect(AppTypographyDesktop.bodyMediumStrong.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.bodySmall.fontSize, 12);
    expect(AppTypographyDesktop.bodySmall.height, 18 / 12);
    expect(AppTypographyDesktop.bodyExtraSmall.fontSize, 11);
    expect(AppTypographyDesktop.bodyExtraSmall.height, 16 / 11);

    expect(AppTypographyDesktop.labelLarge.fontSize, 14);
    expect(AppTypographyDesktop.labelLarge.height, 16 / 14);

    expect(AppTypographyDesktop.labelMedium.fontFamily, 'Geist');
    expect(AppTypographyDesktop.labelMedium.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.labelMedium.fontSize, 13);
    expect(AppTypographyDesktop.labelMedium.height, 14 / 13);
    expect(AppTypographyDesktop.labelMedium.letterSpacing, 0);

    expect(AppTypographyDesktop.labelSmall.fontFamily, 'Geist');
    expect(AppTypographyDesktop.labelSmall.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.labelSmall.fontSize, 13);
    expect(AppTypographyDesktop.labelSmall.height, 14 / 13);

    expect(AppTypographyDesktop.codeSmall.fontFamily, 'Geist Mono');
    expect(AppTypographyDesktop.codeSmall.fontWeight, FontWeight.w500);
    expect(AppTypographyDesktop.codeSmall.fontSize, 13);
    expect(AppTypographyDesktop.codeSmall.height, 17 / 13);
  });

  test('mobile font tokens match 3 Fonts-3.zip', () {
    // Headline XL scales down on mobile (45 -> 40), while Headline M
    // shifts to 24 / 28 with tighter tracking. The zip keeps Libre
    // Caslon Text as the headline family in both modes.
    expect(AppTypographyMobile.displayLarge.fontFamily, 'Libre Caslon Text');
    expect(AppTypographyMobile.displayLarge.fontWeight, FontWeight.w400);
    expect(AppTypographyMobile.displayLarge.fontSize, 40);
    expect(AppTypographyMobile.displayLarge.height, 40 / 40);
    expect(AppTypographyMobile.displayLarge.letterSpacing, -1.35);

    expect(AppTypographyMobile.headlineLarge.fontFamily, 'Libre Caslon Text');
    expect(
      AppTypographyMobile.headlineLarge.fontSize,
      AppTypographyDesktop.headlineLarge.fontSize,
    );
    expect(
      AppTypographyMobile.headlineLarge.height,
      AppTypographyDesktop.headlineLarge.height,
    );
    expect(AppTypographyMobile.headlineMedium.fontFamily, 'Libre Caslon Text');
    expect(AppTypographyMobile.headlineMedium.fontSize, 24);
    expect(AppTypographyMobile.headlineMedium.height, 28 / 24);
    expect(AppTypographyMobile.headlineMedium.letterSpacing, -0.4);

    // Code S is mode-invariant; Code M scales up on mobile.
    expect(AppTypographyMobile.codeMedium.fontSize, 16);
    expect(AppTypographyMobile.codeMedium.height, 21 / 16);
    expect(AppTypographyMobile.codeSmall, AppTypographyDesktop.codeSmall);

    expect(AppTypographyMobile.headlineSmall.fontSize, 18);
    expect(AppTypographyMobile.headlineSmall.height, 22 / 18);

    expect(AppTypographyMobile.bodyLarge.fontSize, 18);
    expect(AppTypographyMobile.bodyLarge.height, 26 / 18);
    expect(AppTypographyMobile.bodyLarge.letterSpacing, -0.24);
    expect(AppTypographyMobile.bodyMedium.fontSize, 16);
    expect(AppTypographyMobile.bodyMedium.height, 25 / 16);
    expect(AppTypographyMobile.bodyMedium.letterSpacing, -0.21);
    expect(AppTypographyMobile.bodyMediumStrong.fontSize, 16);
    expect(AppTypographyMobile.bodyMediumStrong.height, 25 / 16);
    expect(AppTypographyMobile.bodyMediumStrong.fontWeight, FontWeight.w500);
    expect(AppTypographyMobile.bodySmall.fontSize, 14);
    expect(AppTypographyMobile.bodySmall.height, 20 / 14);
    expect(AppTypographyMobile.bodyExtraSmall.fontSize, 13);
    expect(AppTypographyMobile.bodyExtraSmall.height, 18 / 13);

    expect(AppTypographyMobile.labelLarge.fontSize, 16);
    expect(AppTypographyMobile.labelLarge.height, 17 / 16);
    expect(AppTypographyMobile.labelLarge.letterSpacing, -0.06);
    expect(AppTypographyMobile.labelMedium.fontSize, 14);
    expect(AppTypographyMobile.labelMedium.height, 15 / 14);
    expect(AppTypographyMobile.labelSmall, AppTypographyMobile.labelMedium);
  });

  test('semantic color tokens match 2 Color Theme-3.zip', () {
    final light = AppThemeData.light.colors;
    final dark = AppThemeData.dark.colors;

    expect(light.background.window, const Color(0xFFF7F7F7));
    expect(dark.background.window, const Color(0xFF0F0F0F));

    expect(light.background.ground, Primitives.p0Light);
    expect(light.background.base, Primitives.p50Light);
    expect(light.background.raised, Primitives.p100Light);
    expect(light.background.overlay, Primitives.p150Light);
    expect(light.background.neutralScrim, const Color(0x80141818));
    expect(light.background.neutralSubtleOpacity, const Color(0x33B8B8B8));

    expect(dark.background.ground, Primitives.p50Dark);
    expect(dark.background.base, Primitives.p100Dark);
    expect(dark.background.raised, Primitives.p150Dark);
    expect(dark.background.overlay, Primitives.p200Dark);
    expect(dark.background.neutralScrim, const Color(0x80141818));
    expect(dark.background.neutralSubtleOpacity, const Color(0x33626767));

    expect(light.button.disabled.bg, const Color(0x33B8B8B8));
    expect(light.button.disabled.label, const Color(0x80858686));
    expect(dark.button.disabled.bg, const Color(0x334D5252));
    expect(dark.button.disabled.label, const Color(0x80858686));

    expect(light.button.destructive.bg, const Color(0xFF772E89));
    expect(light.button.destructive.bgHover, const Color(0xFF5E2673));
    expect(light.button.destructive.label, const Color(0xFFE6C5EC));
    expect(dark.button.destructive.bg, const Color(0xFF772E89));
    expect(dark.button.destructive.bgHover, const Color(0xFF5E2673));
    expect(dark.button.destructive.label, const Color(0xFFE6C5EC));

    expect(light.icon.success, const Color(0xFF00A460));
    expect(dark.icon.success, const Color(0xFF0DC87D));
    expect(light.text.brandCrimson, const Color(0xFFA83861));
    expect(dark.icon.brandCrimson, const Color(0xFFA83861));

    expect(light.background.utilitySuccessAlpha, const Color(0x263BD38B));
    expect(dark.background.utilitySuccessAlpha, const Color(0x260DC87D));
    expect(light.fade.illustration, Primitives.p0Alpha0Dark);
    expect(dark.fade.illustration, Primitives.p0Alpha50Dark);

    expect(light.state.hover, Primitives.p50Light);
    expect(light.state.hoverOpacity, const Color(0x0D141818));
    expect(light.state.focusRingDestructive, PlumPrimitives.p400Light);
    expect(dark.state.hover, Primitives.p100Dark);
    expect(dark.state.hoverOpacity, const Color(0x26141818));
    expect(dark.state.focusRingDestructive, PlumPrimitives.p200Dark);

    expect(light.shadows.shadow1, Primitives.p150Light);
    expect(light.shadows.shadow2, Primitives.p300Light);
    expect(light.shadows.shadow3, const Color(0x33141818));
    expect(light.shadows.subtle, const Color(0x0D141818));
    expect(light.shadows.regular, const Color(0x1A141818));
    expect(dark.shadows.shadow1, const Color(0x00141818));
    expect(dark.shadows.shadow2, const Color(0x00141818));
    expect(dark.shadows.shadow3, const Color(0x00141818));
    expect(dark.shadows.subtle, const Color(0x00141818));
    expect(dark.shadows.regular, const Color(0x00141818));

    expect(light.sync.glow, GreenPrimitives.p200Light);
    expect(dark.sync.glow, Primitives.p500Dark);
  });

  test('macOS utility color tokens match 2 Color Theme-3.zip', () {
    final light = AppThemeData.light.colors.macosUtility;
    final dark = AppThemeData.dark.colors.macosUtility;

    expect(light.scrollBar, const Color(0x1F1A1A1A));
    expect(light.window, const Color(0xFFF7F7F7));
    expect(light.windowTransparent, const Color(0x00F5F5F5));
    expect(light.navPanel, const Color(0x4DFFFFFF));
    expect(light.disabledStopLight, const Color(0x1A1A1A1A));
    expect(light.font, const Color(0xD91A1A1A));
    expect(light.thinBorder, const Color(0x8CFFFFFF));
    expect(light.innerBorder, const Color(0x3B1A1A1A));

    expect(dark.scrollBar, const Color(0x1FFFFFFF));
    expect(dark.window, const Color(0xFF0F0F0F));
    expect(dark.windowTransparent, const Color(0x000F0F0F));
    expect(dark.navPanel, const Color(0x4D1A1A1A));
    expect(dark.disabledStopLight, const Color(0x1AFFFFFF));
    expect(dark.font, const Color(0xCCFFFFFF));
    expect(dark.thinBorder, const Color(0x3B1A1A1A));
    expect(dark.innerBorder, const Color(0x3B1A1A1A));
  });

  test('plum primitive tokens match 2 Color Theme-3.zip', () {
    expect(PlumPrimitives.p0Light, const Color(0xFFF6ECF9));
    expect(PlumPrimitives.p50Light, const Color(0xFFE6C5EC));
    expect(PlumPrimitives.p300Light, const Color(0xFFAB40BF));
    expect(PlumPrimitives.p400Light, const Color(0xFF9338A7));
    expect(PlumPrimitives.p500Light, const Color(0xFF772E89));
    expect(PlumPrimitives.p900Light, const Color(0xFF0C050E));

    expect(PlumPrimitives.p0Dark, const Color(0xFF0B060D));
    expect(PlumPrimitives.p50Dark, const Color(0xFF2F133A));
    expect(PlumPrimitives.p300Dark, const Color(0xFF9338A7));
    expect(PlumPrimitives.p400Dark, const Color(0xFFAB40BF));
    expect(PlumPrimitives.p500Dark, const Color(0xFFB85BC8));
    expect(PlumPrimitives.p900Dark, const Color(0xFFF6ECF9));

    expect(PlumPrimitives.p400Alpha15Light, const Color(0x269338A7));
    expect(PlumPrimitives.p400Alpha15Dark, const Color(0x26AB40BF));
  });
}
