import 'package:flutter/widgets.dart';

import '../src/features/onboarding/mobile/mobile_method_selection_screen.dart';

Widget buildMobileMethodSelectionCapture(BuildContext context) => MediaQuery(
  data: MediaQuery.of(context).copyWith(
    padding: const EdgeInsets.only(top: 55, bottom: 24),
    viewPadding: const EdgeInsets.only(top: 55, bottom: 24),
  ),
  child: const MobileMethodSelectionScreen(),
);
