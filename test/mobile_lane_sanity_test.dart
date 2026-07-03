@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

void main() {
  // The mobile lane (--tags mobile --run-skipped) lifts the tag's default
  // skip, so this is the guard that catches a forgotten define: it fails
  // first, by name, instead of leaving a pile of confusing wrong-metric
  // failures in the real mobile-UI tests.
  test('mobile lane runs with the mobile token define', () {
    expect(
      kAppFormFactor,
      AppFormFactor.mobile,
      reason:
          'Mobile-tagged tests were compiled with desktop tokens. Add '
          '--dart-define=VIZOR_FORM_FACTOR=mobile to the command.',
    );
  });
}
