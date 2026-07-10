import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../swap/models/swap_activity_navigation.dart';

/// Mobile Pay handoff shown after a software payment intent is accepted.
///
/// Figma: light `6268:85812`, dark `6268:86061`.
class MobilePaySubmittedScreen extends StatelessWidget {
  const MobilePaySubmittedScreen({required this.intentId, super.key});

  final String intentId;

  void _openActivity(BuildContext context) {
    context.go(
      swapActivityDetailUri(
        intentId: intentId,
        returnTarget: SwapActivityReturnTarget.pay,
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = context.appTheme == AppThemeData.dark;
    final backgroundAsset = dark
        ? 'assets/illustrations/pay_submitted_background_dark.png'
        : 'assets/illustrations/pay_submitted_background_light.png';

    return Scaffold(
      backgroundColor: colors.background.window,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(backgroundAsset, fit: BoxFit.cover),
          Positioned(
            left: -319,
            top: -233,
            child: Opacity(
              opacity: 0.15,
              child: Container(
                width: 1031,
                height: 1031,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colors.background.window.withValues(alpha: 0),
                      colors.icon.success,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  Container(
                    key: const ValueKey('pay_submitted_status'),
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.icon.success,
                      shape: BoxShape.circle,
                    ),
                    child: const AppIcon(
                      AppIcons.checkCircle,
                      size: 32,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Payment\nSubmitted',
                    key: const ValueKey('pay_submitted_title'),
                    textAlign: TextAlign.center,
                    style: AppTypography.displayMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'It will confirm on-chain shortly.\nTrack it in Activity.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: 230,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppButton(
                          key: const ValueKey('pay_submitted_done'),
                          expand: true,
                          constrainContent: true,
                          onPressed: () => context.go('/home'),
                          child: const Text('Done'),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        AppButton(
                          key: const ValueKey('pay_submitted_activity'),
                          expand: true,
                          constrainContent: true,
                          variant: AppButtonVariant.ghost,
                          onPressed: () => _openActivity(context),
                          child: const Text('Go to activity'),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
