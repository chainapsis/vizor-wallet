import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

class AddressTypesScreen extends StatelessWidget {
  const AddressTypesScreen({super.key});

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
          'Zcash Address Types',
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text.rich(
          TextSpan(
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
            children: [
              const TextSpan(text: 'Zcash has two addresses types.\nOne for '),
              TextSpan(
                text: 'Privacy',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const TextSpan(text: ', one for '),
              TextSpan(
                text: 'Transparency',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomContent extends StatelessWidget {
  const _BottomContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _CardsRow(),
        SizedBox(height: AppSpacing.base),
        _ActionRow(),
      ],
    );
  }
}

class _CardsRow extends StatelessWidget {
  const _CardsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _ShieldedAddressCard(),
        SizedBox(width: AppSpacing.s),
        _TransparentAddressCard(),
      ],
    );
  }
}

class _ShieldedAddressCard extends StatelessWidget {
  const _ShieldedAddressCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _CardFrame(
      backgroundColor: colors.background.brandCyanSubtle,
      borderColor: colors.border.brandCyanSubtle,
      icon: AppIcon(
        AppIcons.shieldKeyhole,
        size: 32,
        color: colors.icon.brandCyan,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Shielded Address',
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AddressExample(
            badge: 'u1',
            badgeWidth: 24,
            badgeTextColor: colors.text.inverse,
            badgeBackgroundColor: colors.background.brandCyanStrong,
            borderColor: colors.border.brandCyanStrong,
            valueColor: colors.text.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: 256,
            child: Text.rich(
              TextSpan(
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.primary,
                ),
                children: [
                  const TextSpan(text: 'Address starts with '),
                  TextSpan(
                    text: 'u1',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.brandCyan,
                    ),
                  ),
                  const TextSpan(text: ' (or '),
                  TextSpan(
                    text: 'zs',
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.brandCyan,
                    ),
                  ),
                  const TextSpan(text: ' for legacy).\n'),
                  const TextSpan(
                    text:
                        'Only you can see your account balance and transaction '
                        'history.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransparentAddressCard extends StatelessWidget {
  const _TransparentAddressCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _CardFrame(
      backgroundColor: colors.background.base,
      icon: AppIcon(AppIcons.eye, size: 32, color: colors.icon.disabled),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transparent Address',
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _AddressExample(
            badge: 't',
            badgeWidth: 16,
            badgeTextColor: colors.text.primary,
            badgeBackgroundColor: colors.background.overlay,
            borderColor: colors.border.strong,
            valueColor: colors.text.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: 256,
            child: Text(
              "Address starts with t, similar to Bitcoin, your address's "
              'balance and transaction history are publicly visible.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({
    required this.backgroundColor,
    required this.icon,
    required this.child,
    this.borderColor,
  });

  final Color backgroundColor;
  final Color? borderColor;
  final Widget icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 288,
      height: 228,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [icon]),
          child,
        ],
      ),
    );
  }
}

class _AddressExample extends StatelessWidget {
  const _AddressExample({
    required this.badge,
    required this.badgeWidth,
    required this.badgeTextColor,
    required this.badgeBackgroundColor,
    required this.borderColor,
    required this.valueColor,
  });

  final String badge;
  final double badgeWidth;
  final Color badgeTextColor;
  final Color badgeBackgroundColor;
  final Color borderColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: badgeWidth,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBackgroundColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge,
              style: AppTypography.codeMedium.copyWith(color: badgeTextColor),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'vtr241af13x9...XTjFJxxTm3FwF',
            style: AppTypography.codeMedium.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => context.go(OnboardingStep.thingsToKnow.routePath),
      variant: AppButtonVariant.primary,
      minWidth: 196,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: const Text('Continue'),
    );
  }
}
