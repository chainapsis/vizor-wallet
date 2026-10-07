import 'package:flutter/widgets.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../onboarding/shared/onboarding_chrome.dart';

enum DesktopGiftSetupStep { redeem, password, customise }

/// Gift setup shares the desktop password/persona controls, with its own steps.
class DesktopGiftSetupShell extends StatelessWidget {
  const DesktopGiftSetupShell({
    required this.step,
    required this.showPasswordStep,
    required this.child,
    this.backTarget,
    this.overlay,
    super.key,
  });

  final DesktopGiftSetupStep step;
  final bool showPasswordStep;
  final Widget child;
  final OnboardingBackTarget? backTarget;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) => AppDesktopShell(
    backgroundColor: context.colors.background.window,
    sidebar: OnboardingSidebarChrome(
      steps: [
        OnboardingSidebarStepData(
          label: 'Redeem the card',
          iconName: AppIcons.giftCardOutline,
          active: step == DesktopGiftSetupStep.redeem,
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
        child: step == DesktopGiftSetupStep.redeem
            ? SizedBox(
                width: 256,
                height: 430,
                child: Image.asset(
                  context.appTheme == AppThemeData.dark
                      ? 'assets/illustrations/desktop/onboarding_intro_sidebar_dark.webp'
                      : 'assets/illustrations/desktop/onboarding_intro_sidebar_light.webp',
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                ),
              )
            : Image.asset(
                'assets/illustrations/desktop/onboarding_customise_account_sidebar.webp',
                fit: BoxFit.fitWidth,
              ),
      ),
    ),
    pane: OnboardingPaneChrome(
      backTarget: backTarget,
      overlay: overlay,
      child: child,
    ),
  );
}
