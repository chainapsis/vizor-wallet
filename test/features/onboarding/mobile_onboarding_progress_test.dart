@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';

void main() {
  test('create progress counts Welcome before direct Introduction', () {
    expect(kMobileCreateStepCount, 7);
    expect(mobileCreateProgress(1), closeTo(1 / 8, 0.0001));
    expect(mobileCreateProgress(2), closeTo(2 / 8, 0.0001));
    expect(mobileCreateProgress(6), closeTo(6 / 8, 0.0001));
    expect(mobileCreateProgress(7), closeTo(7 / 8, 0.0001));
  });

  test('import advances after selection and reserves terminal completion', () {
    expect(kMobileImportStepCount, 5);
    var previous = kMobileSelectionProgress;
    for (var step = 1; step <= kMobileImportStepCount; step++) {
      final progress = mobileImportProgress(step);
      expect(progress, greaterThan(previous));
      expect(progress, lessThan(1));
      previous = progress;
    }
  });

  test('keystone passcode progress stays on the existing fill', () {
    expect(kMobileKeystonePasscodeProgress, closeTo(5 / 6, 0.0001));
  });
}
