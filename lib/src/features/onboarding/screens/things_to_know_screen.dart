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
          'Things to know',
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Useful tips before you started.',
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
        _InfoCard(
          title: 'How to use Shielded Address',
          body:
              "Some exchanges can't send to shielded addresses. If you're "
              'withdrawing from an exchange, use your transparent address. '
              'You can shield your ZEC after it arrives.',
          iconName: AppIcons.eye,
        ),
        SizedBox(width: AppSpacing.s),
        _InfoCard(
          title: 'Time to sync',
          body:
              'Your wallet syncs directly with the Zcash network instead of '
              'relying on a server. This protects your privacy, but takes a '
              'moment. Your funds are safe while the app catches up.',
          iconName: AppIcons.time,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
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
    return Container(
      width: 288,
      height: 220,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [AppIcon(iconName, size: 32, color: colors.icon.regular)],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 256,
                child: Text(
                  title,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          onPressed: () => context.go('/create'),
          variant: AppButtonVariant.primary,
          minWidth: 196,
          trailing: const AppIcon(AppIcons.chevronForward),
          child: const Text('Generate my wallet'),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          // TODO(onboarding): wire this to an external Zcash resource once
          // the app has a shared URL-launch path.
          onPressed: () {},
          variant: AppButtonVariant.ghost,
          trailing: const AppIcon(AppIcons.link),
          child: const Text('Learn more about Zcash'),
        ),
      ],
    );
  }
}
