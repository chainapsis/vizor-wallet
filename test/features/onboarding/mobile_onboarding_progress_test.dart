@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';

void main() {
  test('create progress includes welcome before method selection', () {
    expect(kMobileCreateStepCount, 8);
    expect(mobileCreateProgress(1), closeTo(1 / 9, 0.0001));
    expect(mobileCreateProgress(2), closeTo(2 / 9, 0.0001));
    expect(mobileCreateProgress(7), closeTo(7 / 9, 0.0001));
    expect(mobileCreateProgress(8), closeTo(8 / 9, 0.0001));
  });

  // 0cd37abda added the customise-account step to the import track.
  test('import progress includes the customise-account step', () {
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
