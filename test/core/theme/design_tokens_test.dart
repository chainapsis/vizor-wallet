import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_icon_size.dart';
import 'package:zcash_wallet/src/core/theme/app_radii.dart';
import 'package:zcash_wallet/src/core/theme/app_sizing.dart';
import 'package:zcash_wallet/src/core/theme/app_spacing.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_data.dart';
import 'package:zcash_wallet/src/core/theme/app_typography.dart';
import 'package:zcash_wallet/src/core/theme/primitives.dart';

void main() {
  test('desktop sizing tokens match 1 Sizing.zip', () {
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

    expect(AppAssetSize.size, 32);
    expect(AppAssetSize.icon, 16);
    expect(AppAssetSize.padding, 4);
    expect(AppIconSize.medium, AppAssetSize.icon);

    expect(AppButtonSizing.largeHeight, 44);

    expect(AppInputSizing.height, 46);
    expect(AppInputSizing.iconWrapWidth, 32);
    expect(AppInputSizing.iconSize, 20);
    expect(AppInputSizing.radius, AppRadii.small);

    expect(AppWindowSizing.minWidth, 1080);
    expect(AppWindowSizing.minHeight, 720);
    expect(AppWindowSizing.maxWidth, 1296);
    expect(AppWindowSizing.maxHeight, 864);
    expect(AppWindowSizing.contentAreaMaxWidth, 420);
    expect(AppWindowSizing.paneRadius, 20);
  });

  test('desktop font tokens match 3 Fonts.zip', () {
    expect(AppTypography.displayMedium.fontFamily, 'Libre Caslon Text');
    expect(AppTypography.displayMedium.fontWeight, FontWeight.w400);
    expect(AppTypography.displayMedium.fontSize, 45);
    expect(AppTypography.displayMedium.height, 48 / 45);
    expect(AppTypography.displayMedium.letterSpacing, -1.35);

    expect(AppTypography.headlineLarge.fontFamily, 'Libre Caslon Text');
    expect(AppTypography.headlineLarge.fontWeight, FontWeight.w400);
    expect(AppTypography.headlineLarge.fontSize, 32);
    expect(AppTypography.headlineLarge.height, 33 / 32);

    expect(AppTypography.headlineMedium.fontFamily, 'Libre Caslon Text');
    expect(AppTypography.headlineMedium.fontWeight, FontWeight.w400);
    expect(AppTypography.headlineMedium.fontSize, 28);
    expect(AppTypography.headlineMedium.height, 30 / 28);
    expect(AppTypography.headlineMedium.letterSpacing, -0.28);

    expect(AppTypography.labelMedium.fontFamily, 'Geist');
    expect(AppTypography.labelMedium.fontWeight, FontWeight.w500);
    expect(AppTypography.labelMedium.fontSize, 13);
    expect(AppTypography.labelMedium.height, 14 / 13);
    expect(AppTypography.labelMedium.letterSpacing, 0);

    expect(AppTypography.labelSmall.fontFamily, 'Geist');
    expect(AppTypography.labelSmall.fontWeight, FontWeight.w500);
    expect(AppTypography.labelSmall.fontSize, 13);
    expect(AppTypography.labelSmall.height, 14 / 13);

    expect(AppTypography.codeSmall.fontFamily, 'Geist Mono');
    expect(AppTypography.codeSmall.fontWeight, FontWeight.w500);
    expect(AppTypography.codeSmall.fontSize, 13);
    expect(AppTypography.codeSmall.height, 17 / 13);
  });

  test('semantic color tokens match 2 Color Theme.zip', () {
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

  test('macOS utility color tokens match 2 Color Theme.zip', () {
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

  test('plum primitive tokens match 2 Color Theme.zip', () {
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
