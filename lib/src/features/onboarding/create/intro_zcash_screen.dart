import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
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
      children: [
        _BackRow(),
        Expanded(
          child: Center(child: SizedBox(width: 500, child: _HeroLayout())),
        ),
      ],
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go('/welcome'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: AppIconSize.medium,
                color: colors.text.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: Center(child: _HeroBlock())),
        _ButtonStack(),
        SizedBox(height: AppSpacing.s),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    final subtitleStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _VizorLogo(),
        const SizedBox(height: AppSpacing.s),
        Text(
          'The Shielded World',
          style: AppTypography.displayMedium.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        Text.rich(
          TextSpan(
            style: subtitleStyle,
            children: [
              const TextSpan(text: 'Zcash (ZEC) built around '),
              TextSpan(
                text: 'financial privacy',
                style: subtitleStyle.copyWith(fontWeight: FontWeight.w500),
              ),
              const TextSpan(text: ' & '),
              TextSpan(
                text: 'self-custody.',
                style: subtitleStyle.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        const AppDecorativeDivider(),
        const SizedBox(height: AppSpacing.s),
        SizedBox(
          width: 384,
          child: Column(
            children: [
              Text(
                'Unlike Bitcoin or Ethereum, shielded Zcash transactions '
                'hide the sender, recipient, and amount — verified by '
                'cryptography, not trust.',
                style: bodyStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You're a few steps away from your first private wallet.\n"
                "Let's get you set up.",
                style: bodyStyle,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VizorLogo extends StatelessWidget {
  const _VizorLogo();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 56,
      height: 28,
      child: SvgPicture.asset(
        'assets/icons/vizor_logo.svg',
        colorFilter: ColorFilter.mode(
          colors.text.brandCrimson,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack();

  static const double _buttonWidth = 256;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          onPressed: () => context.go(OnboardingStep.addressTypes.routePath),
          variant: AppButtonVariant.primary,
          minWidth: _buttonWidth,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: const Text('Tell me how Zcash works'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          onPressed: () =>
              context.go(OnboardingStep.secretPassphrase.routePath),
          variant: AppButtonVariant.ghost,
          minWidth: _buttonWidth,
          trailing: const AppIcon(AppIcons.skip),
          child: const Text('Create New Wallet'),
        ),
      ],
    );
  }
}
