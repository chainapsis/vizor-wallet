import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/onboarding/create/intro_zcash_screen.dart';
import '../src/features/onboarding/create/onboarding_split_view.dart';

/// Uses only local onboarding state, without wallet or native dependencies.
Widget buildDesktopOnboardingIntroCapture(BuildContext context) =>
    const ProviderScope(
      child: OnboardingSplitViewShell(
        activeStep: OnboardingStep.intro,
        showPasswordStep: true,
        child: IntroZcashScreen(),
      ),
    );
