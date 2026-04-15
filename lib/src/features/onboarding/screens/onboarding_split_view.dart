import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';

import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

enum OnboardingStep { intro, addressTypes, thingsToKnow, secretPassphrase }

extension OnboardingStepX on OnboardingStep {
  String get label => switch (this) {
    OnboardingStep.intro => 'Intro to Zcash',
    OnboardingStep.addressTypes => 'Address types',
    OnboardingStep.thingsToKnow => 'Things to know',
    OnboardingStep.secretPassphrase => 'Secret Passphrase',
  };

  String get iconName => switch (this) {
    OnboardingStep.intro => AppIcons.zcash,
    OnboardingStep.addressTypes => AppIcons.shieldKeyhole,
    OnboardingStep.thingsToKnow => AppIcons.crystalBall,
    OnboardingStep.secretPassphrase => AppIcons.key,
  };

  String get routePath => switch (this) {
    OnboardingStep.intro => '/onboarding/intro',
    OnboardingStep.addressTypes => '/onboarding/address-types',
    OnboardingStep.thingsToKnow => '/create',
    OnboardingStep.secretPassphrase => '/create',
  };
}

OnboardingStep onboardingStepFromLocation(String location) {
  if (location.startsWith(OnboardingStep.addressTypes.routePath)) {
    return OnboardingStep.addressTypes;
  }
  if (location.startsWith(OnboardingStep.intro.routePath)) {
    return OnboardingStep.intro;
  }
  return OnboardingStep.intro;
}

class OnboardingSplitViewShell extends StatelessWidget {
  const OnboardingSplitViewShell({
    required this.activeStep,
    required this.child,
    super.key,
  });

  final OnboardingStep activeStep;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1.0);
    final entrance = CurvedAnimation(
      parent: routeAnimation,
      curve: kOnboardingForwardCurve,
      reverseCurve: kOnboardingReverseCurve,
    );
    final sidebarOffset = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(entrance);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SlideTransition(
                position: sidebarOffset,
                child: SizedBox(
                  width: 240,
                  child: _Sidebar(activeStep: activeStep),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: FadeTransition(opacity: entrance, child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingTrailingPane extends StatelessWidget {
  const OnboardingTrailingPane({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.activeStep});

  final OnboardingStep activeStep;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: kOnboardingForwardDuration,
              reverseDuration: kOnboardingReverseDuration,
              switchInCurve: kOnboardingForwardCurve,
              switchOutCurve: kOnboardingReverseCurve,
              transitionBuilder: _fadeTransition,
              child: KeyedSubtree(
                key: ValueKey(activeStep),
                child: _SidebarIllustration(step: activeStep),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: AnimatedSwitcher(
                duration: kOnboardingForwardDuration,
                reverseDuration: kOnboardingReverseDuration,
                switchInCurve: kOnboardingForwardCurve,
                switchOutCurve: kOnboardingReverseCurve,
                transitionBuilder: _fadeTransition,
                child: KeyedSubtree(
                  key: ValueKey(activeStep),
                  child: _SidebarNav(activeStep: activeStep),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fadeTransition(Widget child, Animation<double> animation) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({required this.activeStep});

  final OnboardingStep activeStep;

  static const _steps = [
    OnboardingStep.intro,
    OnboardingStep.addressTypes,
    OnboardingStep.thingsToKnow,
    OnboardingStep.secretPassphrase,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            _NavItem(step: _steps[i], active: _steps[i] == activeStep),
            if (i != _steps.length - 1) const SizedBox(height: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.step, required this.active});

  final OnboardingStep step;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: active ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.xs,
          top: AppSpacing.xxs,
          bottom: AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                step.label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            AppIcon(step.iconName, size: 20, color: colors.icon.accent),
          ],
        ),
      ),
    );
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration({required this.step});

  final OnboardingStep step;

  static const _frameWidth = 240.0;
  static const _frameHeight = 411.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (step) {
      OnboardingStep.addressTypes =>
        isDark
            ? 'assets/illustrations/onboarding_address_types_sidebar_dark.png'
            : 'assets/illustrations/onboarding_address_types_sidebar_light.png',
      _ =>
        isDark
            ? 'assets/illustrations/onboarding_intro_sidebar_dark.png'
            : 'assets/illustrations/onboarding_intro_sidebar_light.png',
    };
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: _frameWidth,
          height: _frameHeight,
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
