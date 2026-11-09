@Tags(['figma-capture'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart' show Tags;
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'locale_layout_scan_support.dart';

void main() {
  runLocaleLayoutScan(
    formFactor: AppFormFactor.desktop,
    logicalSize: const Size(1080, 720),
  );
}
