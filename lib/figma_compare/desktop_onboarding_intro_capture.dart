import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/onboarding/create/intro_zcash_screen.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';
import '../src/features/onboarding/keystone/keystone_onboarding_flow.dart';

/// Uses only local onboarding state, without wallet or native dependencies.
Widget buildDesktopOnboardingIntroCapture(BuildContext context) =>
    const ProviderScope(
      child: OnboardingSplitViewShell(
        activeStep: OnboardingStep.intro,
        showPasswordStep: true,
        child: IntroZcashScreen(),
      ),
    );

/// Exercises shared sidebar chrome without camera or device state.
Widget buildDesktopKeystoneSidebarCapture(BuildContext context) =>
    const KeystoneOnboardingShell(
      activeStep: KeystoneOnboardingStep.customiseAccount,
      showPasswordStep: true,
      child: SizedBox.shrink(),
    );
