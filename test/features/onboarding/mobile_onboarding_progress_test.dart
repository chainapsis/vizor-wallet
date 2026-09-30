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

  test('import progress includes the review step', () {
    expect(kMobileImportStepCount, 5);
    expect(mobileImportProgress(1), closeTo(1 / 6, 0.0001));
    expect(mobileImportProgress(2), closeTo(2 / 6, 0.0001));
    expect(mobileImportProgress(3), closeTo(3 / 6, 0.0001));
    expect(mobileImportProgress(4), closeTo(4 / 6, 0.0001));
    expect(mobileImportProgress(5), closeTo(5 / 6, 0.0001));
  });

  test('keystone passcode progress stays on the existing fill', () {
    expect(kMobileKeystonePasscodeProgress, closeTo(5 / 6, 0.0001));
  });
}
