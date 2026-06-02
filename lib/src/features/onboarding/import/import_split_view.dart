import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
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
      sidebarWidth: 256,
      showSidebar: isDesktopLayoutPlatform,
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
    this.overlay,
    super.key,
  });

  final Widget child;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    final overlay = this.overlay;
    if (overlay == null) {
      return AppDesktopPane(child: child);
    }

    return AppDesktopPane(
      padding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
          overlay,
        ],
      ),
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
                    _ImportSidebarItem(
                      label: _steps[i].label,
                      iconName: _steps[i].iconName,
                      active: _steps[i] == activeStep,
                    ),
                    if (i != _steps.length - 1)
                      const SizedBox(height: AppSpacing.xs),
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

class _ImportSidebarItem extends StatelessWidget {
  const _ImportSidebarItem({
    required this.label,
    required this.iconName,
    required this.active,
  });

  final String label;
  final String iconName;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: active ? colors.state.selectedOpacity : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          AppIcon(iconName, size: 20, color: colors.icon.accent),
          const SizedBox(width: AppSpacing.s),
          Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
        ],
      ),
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
