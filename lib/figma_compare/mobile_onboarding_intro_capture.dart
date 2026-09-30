import 'package:flutter/widgets.dart';

import '../src/features/onboarding/mobile/mobile_create_steps.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import '../src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';

/// Match the reference's status-bar and bottom-inset space without rendering
/// operating-system chrome. The screen has no wallet, storage, or network state.
Widget buildMobileOnboardingIntroCapture(BuildContext context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: const EdgeInsets.only(top: 55, bottom: 24),
    viewPadding: const EdgeInsets.only(top: 55, bottom: 24),
  ),
  child: const MobileOnboardingProgressScope(
    setupMode: OnboardingSetupMode.createPasscode,
    child: MobileOnboardingIntroScreen(),
  ),
);
