@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';

void main() {
  test('create progress includes welcome before method selection', () {
    expect(kMobileCreateStepCount, 7);
    expect(mobileCreateProgress(1), closeTo(0.125, 0.0001));
    expect(mobileCreateProgress(2), closeTo(0.25, 0.0001));
    expect(mobileCreateProgress(7), closeTo(0.875, 0.0001));
  });

  test('import progress includes the review step', () {
    expect(kMobileImportStepCount, 4);
    expect(mobileImportProgress(1), closeTo(0.2, 0.0001));
    expect(mobileImportProgress(2), closeTo(0.4, 0.0001));
    expect(mobileImportProgress(3), closeTo(0.6, 0.0001));
    expect(mobileImportProgress(4), closeTo(0.8, 0.0001));
  });

  test('keystone passcode progress stays on the existing fill', () {
    expect(kMobileKeystonePasscodeProgress, closeTo(5 / 6, 0.0001));
  });
}
