import 'package:flutter/widgets.dart';

import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';

Widget buildMobileWelcomeCapture(BuildContext context) =>
    const MobileWelcomeScreen(animateBackground: false);

Widget buildMobileAddAccountWelcomeCapture(BuildContext context) =>
    const MobileWelcomeScreen(showBackButton: true, animateBackground: false);
