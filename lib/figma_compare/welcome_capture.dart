import 'package:flutter/widgets.dart';

import '../src/features/onboarding/mobile/mobile_welcome_screen.dart';
import '../widgetbook/screen_use_cases.dart';

Widget buildDesktopWelcomeCapture(BuildContext context) =>
    buildWelcomeLargeUseCase(context);

Widget buildDesktopAddAccountWelcomeCapture(BuildContext context) =>
    buildWelcomeLargeUseCase(context, showBackButton: true);

Widget buildMobileWelcomeCapture(BuildContext context) =>
    const MobileWelcomeScreen(animateBackground: false);

Widget buildMobileAddAccountWelcomeCapture(BuildContext context) =>
    const MobileWelcomeScreen(showBackButton: true, animateBackground: false);
