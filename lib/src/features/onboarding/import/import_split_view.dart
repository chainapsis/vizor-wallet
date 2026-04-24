import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/motion/onboarding_motion.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

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
  const ImportOnboardingTrailingPane({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppDesktopPane(child: child);
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
    return AppDesktopSidebarSurface(
      child: Stack(
        children: [
          const Positioned.fill(child: _SidebarIllustration()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _steps.length; i++) ...[
                    AppSidebarItem(
                      label: _steps[i].label,
                      iconName: _steps[i].iconName,
                      active: _steps[i] == activeStep,
                    ),
                    if (i != _steps.length - 1)
                      const SizedBox(height: AppSpacing.xxs),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarIllustration extends StatelessWidget {
  const _SidebarIllustration();

  static const _frameWidth = 240.0;
  static const _frameHeight = 411.0;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final asset = isDark
        ? 'assets/illustrations/onboarding_secret_passphrase_sidebar_dark.png'
        : 'assets/illustrations/onboarding_secret_passphrase_sidebar_light.png';
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
