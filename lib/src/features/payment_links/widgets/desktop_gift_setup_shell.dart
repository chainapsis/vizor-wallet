import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../onboarding/shared/onboarding_chrome.dart';

enum DesktopGiftSetupStep { password, customise }

/// Gift setup shares the desktop password/persona controls, with its own steps.
class DesktopGiftSetupShell extends StatelessWidget {
  const DesktopGiftSetupShell({
    required this.step,
    required this.showPasswordStep,
    required this.child,
    this.overlay,
    super.key,
  });

  final DesktopGiftSetupStep step;
  final bool showPasswordStep;
  final Widget child;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => AppDesktopShell(
    backgroundColor: context.colors.background.window,
    sidebar: OnboardingSidebarChrome(
      steps: [
        const OnboardingSidebarStepData(
          label: 'Gift card',
          iconName: AppIcons.giftCard,
          active: false,
        ),
        if (showPasswordStep)
          OnboardingSidebarStepData(
            label: 'Set Password',
            iconName: AppIcons.lock,
            active: step == DesktopGiftSetupStep.password,
          ),
        OnboardingSidebarStepData(
          label: 'Customise wallet',
          iconName: AppIcons.user,
          active: step == DesktopGiftSetupStep.customise,
        ),
      ],
      illustration: Align(
        alignment: Alignment.bottomCenter,
        child: Image.asset(
          'assets/illustrations/onboarding_customise_account_sidebar.png',
          fit: BoxFit.fitWidth,
        ),
      ),
    ),
    pane: OnboardingPaneChrome(overlay: overlay, child: child),
  );
}
