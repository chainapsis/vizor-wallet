import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../onboarding/shared/onboarding_chrome.dart';

export '../../onboarding/shared/onboarding_chrome.dart'
    show OnboardingBackTarget;

enum MultisigOnboardingStep { connect, sessionSetup, backup, setPassword }

extension MultisigOnboardingStepX on MultisigOnboardingStep {
  // Sidebar step labels use the onboarding Title Case convention.
  String get label => switch (this) {
    MultisigOnboardingStep.connect => 'Connect Multisig',
    MultisigOnboardingStep.sessionSetup => 'Session Setup',
    MultisigOnboardingStep.backup => 'Backup',
    MultisigOnboardingStep.setPassword => 'Set Password',
  };

  String get iconName => switch (this) {
    MultisigOnboardingStep.connect => AppIcons.users,
    MultisigOnboardingStep.sessionSetup => AppIcons.link,
    MultisigOnboardingStep.backup => AppIcons.key,
    MultisigOnboardingStep.setPassword => AppIcons.lock,
  };
}

MultisigOnboardingStep multisigOnboardingStepFromLocation(String location) {
  if (location.startsWith('/multisig/set-password')) {
    return MultisigOnboardingStep.setPassword;
  }
  if (location.startsWith('/multisig/session/')) {
    return MultisigOnboardingStep.backup;
  }
  if (location.startsWith('/multisig/create') ||
      location.startsWith('/multisig/join')) {
    return MultisigOnboardingStep.sessionSetup;
  }
  return MultisigOnboardingStep.connect;
}

class MultisigOnboardingShell extends StatelessWidget {
  const MultisigOnboardingShell({
    required this.activeStep,
    required this.child,
    this.showPasswordStep,
    super.key,
  });

  final MultisigOnboardingStep activeStep;
  final bool? showPasswordStep;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showPasswordStep =
        this.showPasswordStep ??
        activeStep == MultisigOnboardingStep.setPassword;
    final routeAnimation =
        ModalRoute.of(context)?.animation ??
        const AlwaysStoppedAnimation<double>(1.0);
    final entrance = CurvedAnimation(
      parent: routeAnimation,
      curve: kOnboardingForwardCurve,
      reverseCurve: kOnboardingReverseCurve,
    );

    return AppDesktopShell(
      sidebarWidth: 256,
      background: _MultisigOnboardingWindowBackground(activeStep: activeStep),
      sidebar: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(entrance),
        child: _Sidebar(
          activeStep: activeStep,
          showPasswordStep: showPasswordStep,
        ),
      ),
      pane: FadeTransition(opacity: entrance, child: child),
    );
  }
}

class _MultisigOnboardingWindowBackground extends StatelessWidget {
  const _MultisigOnboardingWindowBackground({required this.activeStep});

  final MultisigOnboardingStep activeStep;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (activeStep) {
      MultisigOnboardingStep.backup =>
        isDark
            ? 'assets/illustrations/onboarding_secret_passphrase_background_dark.png'
            : 'assets/illustrations/onboarding_secret_passphrase_background_light.png',
      MultisigOnboardingStep.setPassword =>
        'assets/illustrations/onboarding_set_password_background_light.png',
      _ => null,
    };

    if (asset == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(color: context.colors.background.window),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
    );
  }
}

class MultisigOnboardingTrailingPane extends StatelessWidget {
  const MultisigOnboardingTrailingPane({
    required this.child,
    this.backTarget,
    this.overlay,
    this.bodyPadding = const EdgeInsets.fromLTRB(12, 16, 12, 16),
    super.key,
  });

  final Widget child;
  final OnboardingBackTarget? backTarget;
  final Widget? overlay;
  final EdgeInsetsGeometry bodyPadding;

  @override
  Widget build(BuildContext context) {
    return OnboardingPaneChrome(
      backTarget: backTarget,
      overlay: overlay,
      bodyPadding: bodyPadding,
      child: child,
    );
  }
}

class MultisigOnboardingTitle extends StatelessWidget {
  const MultisigOnboardingTitle({
    required this.title,
    required this.subtitle,
    required this.iconName,
    super.key,
  });

  final String title;
  final String subtitle;
  final String iconName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.state.selectedOpacity,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: AppIcon(iconName, size: 22, color: colors.icon.accent),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppTypography.displaySmall.copyWith(
            color: colors.text.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.activeStep, required this.showPasswordStep});

  final MultisigOnboardingStep activeStep;
  final bool showPasswordStep;

  List<MultisigOnboardingStep> get _steps => [
    MultisigOnboardingStep.connect,
    MultisigOnboardingStep.sessionSetup,
    MultisigOnboardingStep.backup,
    if (showPasswordStep) MultisigOnboardingStep.setPassword,
  ];

  @override
  Widget build(BuildContext context) {
    return OnboardingSidebarChrome(
      steps: [
        for (final step in _steps)
          OnboardingSidebarStepData(
            label: step.label,
            iconName: step.iconName,
            active: step == activeStep,
          ),
      ],
      illustration: AnimatedSwitcher(
        duration: kOnboardingForwardDuration,
        reverseDuration: kOnboardingReverseDuration,
        switchInCurve: kOnboardingForwardCurve,
        switchOutCurve: kOnboardingReverseCurve,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey(activeStep.name),
          child: _SidebarIllustration(activeStep: activeStep),
        ),
      ),
    );
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration({required this.activeStep});

  final MultisigOnboardingStep activeStep;

  static const _frameWidth = 256.0;
  static const _frameHeight = 405.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = switch (activeStep) {
      MultisigOnboardingStep.connect =>
        isDark
            ? 'assets/illustrations/onboarding_intro_sidebar_dark.png'
            : 'assets/illustrations/onboarding_intro_sidebar_light.png',
      MultisigOnboardingStep.sessionSetup =>
        isDark
            ? 'assets/illustrations/onboarding_address_types_sidebar_dark.png'
            : 'assets/illustrations/onboarding_address_types_sidebar_light.png',
      MultisigOnboardingStep.backup =>
        isDark
            ? 'assets/illustrations/onboarding_secret_passphrase_sidebar_closed_dark.png'
            : 'assets/illustrations/onboarding_secret_passphrase_sidebar_closed_light.png',
      MultisigOnboardingStep.setPassword =>
        isDark
            ? 'assets/illustrations/onboarding_set_password_sidebar_dark.png'
            : 'assets/illustrations/onboarding_set_password_sidebar_light.png',
    };

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: _frameWidth,
          height: _frameHeight,
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }
}
