import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

class ThingsToKnowScreen extends StatelessWidget {
  const ThingsToKnowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingTrailingPane(
      backTarget: OnboardingBackTarget.route(
        label: OnboardingStep.addressTypes.label,
        routePath: OnboardingStep.addressTypes.routePath,
      ),
      child: const _HeroLayout(),
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
        SizedBox(height: AppSpacing.md),
        _ButtonStack(),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Things to Know',
          style: AppTypography.displayLarge.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'A few tips before you start.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _InfoColumns(),
      ],
    );
  }
}

class _InfoColumns extends StatelessWidget {
  const _InfoColumns();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoColumn(
            title: 'Time to sync',
            body:
                'Your balance may be incomplete until your wallet finishes '
                'syncing. Syncing directly with the Zcash network protects '
                'your privacy, but takes time. Your funds are safe in the '
                'meantime.',
            iconName: AppIcons.time,
          ),
          const SizedBox(width: AppSpacing.lg),
          Container(
            width: 1,
            height: 145,
            decoration: BoxDecoration(
              color: colors.background.inverse.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          const _InfoColumn(
            title: 'How to keep privacy',
            body:
                "Most exchanges don't let you withdraw to a shielded address. "
                'Use your transparent address, then shield your ZEC after it '
                'arrives.',
            iconName: AppIcons.shieldKeyholeOutline,
          ),
        ],
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({
    required this.title,
    required this.body,
    required this.iconName,
  });

  final String title;
  final String body;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 256,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(iconName, size: 20, color: colors.text.brandCrimson),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonStack extends StatelessWidget {
  const _ButtonStack();

  static const double _buttonWidth = 256;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => context.go(OnboardingStep.secretPassphrase.routePath),
      variant: AppButtonVariant.primary,
      minWidth: _buttonWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: const Text('Good to know'),
    );
  }
}
