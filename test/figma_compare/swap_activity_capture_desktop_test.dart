@Tags(['figma-capture'])
library;

import 'package:flutter_test/flutter_test.dart' show Tags;
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

import 'swap_activity_capture_support.dart';

void main() => runSwapActivityCaptures(AppFormFactor.desktop);
