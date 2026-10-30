import 'package:flutter/widgets.dart';

import '../widgetbook/screen_use_cases.dart';

Widget buildDesktopWelcomeCapture(BuildContext context) =>
    buildWelcomeLargeUseCase(context, animateBackground: false);

Widget buildDesktopAddAccountWelcomeCapture(BuildContext context) =>
    buildWelcomeLargeUseCase(
      context,
      showBackButton: true,
      animateBackground: false,
    );
