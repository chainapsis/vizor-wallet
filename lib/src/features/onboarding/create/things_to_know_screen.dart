import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
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
        label: OnboardingStep.addressTypes.label(context),
        routePath: OnboardingStep.addressTypes.routePath,
      ),
      bodyPadding: EdgeInsets.zero,
      child: const _HeroLayout(),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout();

  static const double _contentAreaWidth = 420;
  static const double _contentPaddingX = 12;
  static const double _contentPaddingY = 16;

  @override
  Widget build(BuildContext context) {
    return const Column(
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
                    Expanded(child: _OnPageContent()),
                    _ButtonStack(),
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
            AppLocalizations.of(context).onbThingsToKnow,
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppLocalizations.of(context).onbTwoAddressTypes,
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
            title: AppLocalizations.of(context).onbTimeToSync,
            body:
                AppLocalizations.of(context).onbTimeToSyncBody,
            iconName: AppIcons.time,
          ),
          SizedBox(height: AppSpacing.sm),
          _Divider(),
          SizedBox(height: AppSpacing.sm),
          _InfoSection(
            title: AppLocalizations.of(context).onbKeepPrivacy,
            body:
                AppLocalizations.of(context).onbKeepPrivacyBody,
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
  const _ButtonStack();

  static const double _buttonWidth = 196;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => context.go(OnboardingStep.secretPassphrase.routePath),
      variant: AppButtonVariant.primary,
      minWidth: _buttonWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: Text(AppLocalizations.of(context).onbTellMeHow),
    );
  }
}
