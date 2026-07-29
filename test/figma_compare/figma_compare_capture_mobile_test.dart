@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show Tags;
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'figma_compare_capture_support.dart';

void main() {
  runFigmaCompareCaptureTest(
    expectedFormFactor: AppFormFactor.mobile,
    defaultLogicalSize: const Size(393, 852),
    defaultPixelRatio: 3,
  );
}
