import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/donation/donation_config.dart';

void main() {
  test('donation is available only on mainnet', () {
    expect(donationFeatureEnabledForNetwork('main'), isTrue);
    expect(donationFeatureEnabledForNetwork(' main '), isTrue);
    expect(donationFeatureEnabledForNetwork('test'), isFalse);
    expect(donationFeatureEnabledForNetwork('regtest'), isFalse);
    expect(donationFeatureEnabledForNetwork('unknown'), isFalse);
    expect(donationFeatureEnabledForNetwork(''), isFalse);
  });

  test('donation address stays aligned with README', () {
    final readme = File('README.md').readAsStringSync();
    expect(kVizorDonationAddress, startsWith('u1'));
    expect(readme, contains(kVizorDonationAddress));
  });
}
