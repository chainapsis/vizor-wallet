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

  test('import progress reflects the review screen removal', () {
    expect(kMobileImportStepCount, 3);
    expect(mobileImportProgress(1), closeTo(0.25, 0.0001));
    expect(mobileImportProgress(2), closeTo(0.5, 0.0001));
    expect(mobileImportProgress(3), closeTo(0.75, 0.0001));
  });

  test('keystone passcode progress stays on the existing fill', () {
    expect(kMobileKeystonePasscodeProgress, closeTo(5 / 6, 0.0001));
  });
}
