import 'package:flutter/widgets.dart';

import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';
import '../src/providers/network_privacy_provider.dart';
import '../widgetbook/mobile_welcome_preview_scope.dart';

Widget buildMobileWelcomeCapture(BuildContext context) =>
    mobileWelcomePreviewScope(
      state: const NetworkPrivacyState.off(),
      child: const MobileWelcomeScreen(animateBackground: false),
    );

Widget buildMobileAddAccountWelcomeCapture(BuildContext context) =>
    mobileWelcomePreviewScope(
      state: const NetworkPrivacyState.off(),
      child: const MobileWelcomeScreen(
        showBackButton: true,
        animateBackground: false,
      ),
    );
