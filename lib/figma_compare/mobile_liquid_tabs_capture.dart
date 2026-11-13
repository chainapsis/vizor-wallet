// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';

import '../widgetbook/screen_use_cases.dart';

/// The general capture harness requests reduced motion. Explicitly preview the
/// resting glass surface here, rather than its reduced-motion fallback.
Widget buildMobileLiquidTabsCapture(BuildContext context) {
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: false),
    child: Builder(builder: buildMobileHomeDefaultUseCase),
  );
}
