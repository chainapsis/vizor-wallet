import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

class ThingsToKnowScreen extends StatelessWidget {
  const ThingsToKnowScreen({
    this.onContinue,
    this.backTarget,
    this.actionsEnabled = true,
    super.key,
  });
  final VoidCallback? onContinue;
  final OnboardingBackTarget? backTarget;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context) {
    return OnboardingTrailingPane(
      backTarget:
          backTarget ??
          OnboardingBackTarget.route(
            label: OnboardingStep.addressTypes.label(context.l10n),
            routePath: OnboardingStep.addressTypes.routePath,
          ),
      bodyPadding: EdgeInsets.zero,
      child: _HeroLayout(
        onContinue: onContinue,
        actionsEnabled: actionsEnabled,
      ),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout({this.onContinue, required this.actionsEnabled});
  final VoidCallback? onContinue;
  final bool actionsEnabled;

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SizedBox(
              width: _contentAreaWidth,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _contentPaddingX,
                  vertical: _contentPaddingY,
                ),
                child: Column(
                  children: [
                    const Expanded(child: _OnPageContent()),
                    _ButtonStack(
                      onContinue: onContinue,
                      actionsEnabled: actionsEnabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnPageContent extends StatelessWidget {
  const _OnPageContent();

  static const double _sectionGap = 32;

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TitleBlock(),
        SizedBox(height: _sectionGap),
        _ThingsToKnowPanel(),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            context.l10n.onboardingThingsToKnow,
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.onboardingAddressTypesSubtitle,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.accent,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ThingsToKnowPanel extends StatelessWidget {
  const _ThingsToKnowPanel();

  static const _radius = BorderRadius.all(Radius.circular(24));
  static const double _verticalPadding = 32;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fill = colors.background.ground;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: _verticalPadding,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: Column(
        children: [
          _InfoSection(
            title: context.l10n.onboardingThingsTimeToSyncTitle,
            body: context.l10n.onboardingThingsTimeToSyncBody,
            iconName: AppIcons.time,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Divider(),
          const SizedBox(height: AppSpacing.sm),
          _InfoSection(
            title: context.l10n.onboardingThingsKeepPrivacyTitle,
            body: context.l10n.onboardingThingsKeepPrivacyBody,
            iconName: AppIcons.shieldKeyholeOutline,
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.border.regular,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: const SizedBox(height: 1, width: double.infinity),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppIcon(iconName, size: 24, color: colors.icon.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
  const _ButtonStack({this.onContinue, required this.actionsEnabled});
  final VoidCallback? onContinue;
  final bool actionsEnabled;

  static const double _buttonWidth = 196;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      key: const ValueKey('desktop_education_continue'),
      onPressed: actionsEnabled
          ? onContinue ??
                () => context.go(OnboardingStep.secretPassphrase.routePath)
          : null,
      variant: AppButtonVariant.primary,
      minWidth: _buttonWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: Text(context.l10n.onboardingTellMeHowZcashWorks),
    );
  }
}
