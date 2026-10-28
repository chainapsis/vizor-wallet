@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../../support/swap_activity_privacy_checks.dart';

void main() {
  registerSwapActivityPrivacyChecks(mobile: true);
}
