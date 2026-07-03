import 'package:flutter/widgets.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../../l10n/app_localizations.dart';

/// Mobile deposit-timeout state — Figma `Swap failed` (4755:89127):
/// the fallen-knight illustration, the "Time's up" tag, the serif
/// headline, and the restart action. The host's top nav carries the
/// "Swap failed" title, so it doesn't repeat here.
class MobileSwapTimeoutContent extends StatelessWidget {
  const MobileSwapTimeoutContent({required this.onRestart, super.key});

  static const _illustration =
      'assets/illustrations/swap_failed_illustration.png';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                        AppLocalizations.of(context).swapTimesUp,
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
                      AppLocalizations.of(context).swapTimeoutInvalidAddress,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: _headlineStyle.copyWith(color: colors.text.accent),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    AppLocalizations.of(context).swapTimeoutStartAnother,
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
              child: Text(AppLocalizations.of(context).swapRestartSwap),
            ),
          ],
        ),
      ),
    );
  }
}
