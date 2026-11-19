import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../swap_support_notice.dart';

/// Mobile deposit-timeout state — Figma `Swap failed` (4755:89127):
/// the fallen-knight illustration, the "Time's up" tag, the serif
/// headline, and the restart action. The host's top nav carries the
/// "Swap failed" title, so it doesn't repeat here.
class MobileSwapTimeoutContent extends StatelessWidget {
  const MobileSwapTimeoutContent({
    required this.onRestart,
    this.onLateDeposit,
    this.depositClaimed = false,
    super.key,
  });

  static const _illustration =
      'assets/illustrations/swap_failed_illustration.webp';
  static const _contentWidth = 340.0;
  static const _messageWidth = 300.0;
  static const _headlineWidth = 217.0;
  static const _illustrationHeight = 220.0;
  static const _buttonHeight = 36.0;
  static const _buttonMinWidth = 96.0;

  static const _headlineStyle = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w400,
    fontSize: 24,
    height: 28 / 24,
    letterSpacing: 0,
    fontFeatures: [FontFeature.liningFigures()],
  );

  final VoidCallback onRestart;
  final VoidCallback? onLateDeposit;

  /// Whether the user said they sent the deposit. Such a timeout explains
  /// that it went undetected and offers help instead of asking whether they
  /// sent one.
  final bool depositClaimed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lateDeposit = onLateDeposit;
    final claimed = depositClaimed && lateDeposit != null;
    return Center(
      child: SizedBox(
        key: const ValueKey('mobile_swap_timeout_content'),
        width: _contentWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              _illustration,
              key: const ValueKey('mobile_swap_timeout_illustration'),
              width: _contentWidth,
              height: _illustrationHeight,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: AppSpacing.base),
            SizedBox(
              key: const ValueKey('mobile_swap_timeout_message'),
              width: _messageWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIcons.time,
                        size: 20,
                        color: colors.text.secondary,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        context.l10n.commonTimeSUp,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: _headlineWidth,
                    child: Text(
                      claimed
                          ? context.l10n.swapTimeoutClaimedHeadline
                          : context.l10n.swapTimeoutHeadline,
                      textAlign: TextAlign.center,
                      style: _headlineStyle.copyWith(color: colors.text.accent),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    claimed
                        ? context.l10n.swapTimeoutClaimedBody
                        : context.l10n.swapTimeoutBody,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            AppButton(
              key: const ValueKey('mobile_swap_timeout_restart'),
              onPressed: onRestart,
              variant: AppButtonVariant.secondary,
              height: _buttonHeight,
              minWidth: _buttonMinWidth,
              leading: const AppIcon(AppIcons.renew, size: 20),
              child: Text(context.l10n.swapTimeoutRestart),
            ),
            if (lateDeposit != null) ...[
              const SizedBox(height: AppSpacing.xs),
              claimed
                  ? SwapSupportPrompt.depositClaimed(onTap: lateDeposit)
                  : SwapSupportPrompt(onTap: lateDeposit, failedSwap: false),
            ],
          ],
        ),
      ),
    );
  }
}
