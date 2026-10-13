import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/private_transparent_recovery_config.dart';
import 'package:zcash_wallet/src/providers/enhance_pir_provider.dart';

void main() {
  test('the regtest harness allowance is off without its define', () {
    // Tests run as debug builds, so the define alone keeps it off here.
    expect(kZcashE2ePrivateTransparentRegtest, isFalse);
    expect(isEnhancePirAvailableForNetwork('regtest'), isFalse);
  });

  test('private queries always describes transparent recovery', () {
    expect(
      kPrivateQueriesSettingsCopy,
      'Experimental. Recovers transparent funds privately, preventing the '
      'server from learning your transparent addresses. Looks up supported '
      'transactions without revealing their IDs to servers.',
    );
  });
}
