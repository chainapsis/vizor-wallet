import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../shared/onboarding_chrome.dart';

export '../shared/onboarding_chrome.dart' show OnboardingBackTarget;

enum ImportOnboardingStep {
  secretPassphrase,
  walletBirthdayHeight,
  setPassword,
}

extension ImportOnboardingStepX on ImportOnboardingStep {
  String get label => switch (this) {
    ImportOnboardingStep.secretPassphrase => 'Secret Passphrase',
    ImportOnboardingStep.walletBirthdayHeight => 'Wallet Birthday Height',
    ImportOnboardingStep.setPassword => 'Set Password',
  };

  String get iconName => switch (this) {
    ImportOnboardingStep.secretPassphrase => AppIcons.key,
    ImportOnboardingStep.walletBirthdayHeight => AppIcons.block,
    ImportOnboardingStep.setPassword => AppIcons.lock,
  };
}

ImportOnboardingStep importOnboardingStepFromLocation(String location) {
  if (location.startsWith('/import/set-password')) {
    return ImportOnboardingStep.setPassword;
  }
  if (location.startsWith('/import/birthday')) {
    return ImportOnboardingStep.walletBirthdayHeight;
  }
  return ImportOnboardingStep.secretPassphrase;
}

class ImportOnboardingShell extends StatelessWidget {
  const ImportOnboardingShell({
    required this.activeStep,
    required this.showPasswordStep,
    required this.child,
    super.key,
  });

  final ImportOnboardingStep activeStep;
  final bool showPasswordStep;
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

    return AppDesktopShell(
      sidebarWidth: 256,
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

class ImportOnboardingTrailingPane extends StatelessWidget {
  const ImportOnboardingTrailingPane({
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

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.activeStep, required this.showPasswordStep});

  final ImportOnboardingStep activeStep;
  final bool showPasswordStep;

  List<ImportOnboardingStep> get _steps => [
    ImportOnboardingStep.secretPassphrase,
    ImportOnboardingStep.walletBirthdayHeight,
    if (showPasswordStep) ImportOnboardingStep.setPassword,
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
      illustration: const _SidebarIllustration(),
    );
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration();

  static const _frameWidth = 256.0;
  static const _frameHeight = 405.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/onboarding_intro_sidebar_dark.png'
        : 'assets/illustrations/onboarding_intro_sidebar_light.png';
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
