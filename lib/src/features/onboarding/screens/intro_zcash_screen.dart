import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

/// Onboarding step 1 — "Intro to Zcash".
///
/// This widget now renders only the trailing pane content. The shared
/// split-view shell (sidebar, illustration, acrylic gap) lives in
/// `onboarding_split_view.dart` so subsequent onboarding steps can reuse
/// the same left rail while only the right pane cross-fades.
class IntroZcashScreen extends StatelessWidget {
  const IntroZcashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingTrailingPane(child: _Content());
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [_Title(), _BottomContent()],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to\nthe Shielded World',
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Zcash (ZEC) built around financial privacy & self-custody.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _BottomContent extends StatelessWidget {
  const _BottomContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 384,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unlike Bitcoin or Ethereum, shielded Zcash transactions '
                'hide the sender, recipient, and amount — verified by '
                'cryptography, not trust.',
                style: bodyStyle,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You're a few steps away from your first private wallet.\n"
                "Let's get you set up.",
                style: bodyStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.base),
        const _ActionRow(),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          onPressed: () => context.go(OnboardingStep.addressTypes.routePath),
          variant: AppButtonVariant.primary,
          minWidth: 196,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: const Text('Start Onboarding'),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          onPressed: () => context.go('/create'),
          variant: AppButtonVariant.ghost,
          trailing: const AppIcon(AppIcons.skip),
          child: const Text('Skip'),
        ),
      ],
    );
  }
}
