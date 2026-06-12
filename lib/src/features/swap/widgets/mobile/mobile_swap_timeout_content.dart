import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';

/// Mobile deposit-timeout state — Figma `Swap failed` (4752:28424):
/// the fallen-knight illustration, the "Time's up" tag, the serif
/// headline, and the restart action. The host's top nav carries the
/// "Swap failed" title, so it doesn't repeat here.
class MobileSwapTimeoutContent extends StatelessWidget {
  const MobileSwapTimeoutContent({required this.onRestart, super.key});

  static const _lightIllustration =
      'assets/illustrations/swap_deposit_timeout_illustration_light.png';
  static const _darkIllustration =
      'assets/illustrations/swap_deposit_timeout_illustration_dark.png';

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return Column(
      key: const ValueKey('mobile_swap_timeout_content'),
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          isDark ? _darkIllustration : _lightIllustration,
          width: 210,
          height: 160,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: AppSpacing.base),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.time,
              size: AppIconSize.medium,
              color: colors.text.secondary,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'Time’s up',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'This deposit address\nis no longer valid',
          textAlign: TextAlign.center,
          style: AppTypography.headlineMedium.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Please, start another swap transaction.',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        AppButton(
          key: const ValueKey('mobile_swap_timeout_restart'),
          onPressed: onRestart,
          variant: AppButtonVariant.secondary,
          leading: const AppIcon(AppIcons.renew),
          child: const Text('Restart swap'),
        ),
      ],
    );
  }
}
