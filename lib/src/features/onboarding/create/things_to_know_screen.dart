import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

class ThingsToKnowScreen extends StatelessWidget {
  const ThingsToKnowScreen({super.key});

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
          child: Center(child: SizedBox(width: 588, child: _HeroLayout())),
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
        onTap: () => context.go(OnboardingStep.addressTypes.routePath),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Things to Know',
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Useful tips before you started.',
          style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        const AppDecorativeDivider(),
        const SizedBox(height: AppSpacing.s),
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: _InfoColumn(
              title: 'Time to sync',
              body:
                  'Your wallet syncs directly with the Zcash network instead '
                  'of relying on a server. This protects your privacy, but '
                  'takes a moment. Your funds are safe while the app catches '
                  'up.',
              iconName: AppIcons.time,
            ),
          ),
          Container(
            width: 1,
            height: 140,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            color: colors.text.primary.withValues(alpha: 0.2),
          ),
          const Expanded(
            child: _InfoColumn(
              title: 'How to keep privacy',
              body:
                  "Some exchanges can't send to shielded addresses. If you're "
                  'withdrawing from an exchange, use your transparent address. '
                  'You can shield your ZEC after it arrives.',
              iconName: AppIcons.shieldKeyholeOutline,
            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(iconName, size: 20, color: colors.text.brandCrimson),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 256,
          child: Text(
            body,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ),
      ],
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
