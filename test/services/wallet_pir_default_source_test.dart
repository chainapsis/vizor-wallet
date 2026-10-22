import 'package:flutter_test/flutter_test.dart';

import 'package:zcash_wallet/src/services/wallet_pir/wallet_pir_config.dart';

void main() {
  test('mainnet always uses the fixed source and other networks have none', () {
    const network = String.fromEnvironment(
      'ZCASH_DEFAULT_NETWORK',
      defaultValue: 'main',
    );
    if (network == 'main') {
      expect(defaultWalletPirConfigSource(), kProductionWalletPirConfigSource);
    } else {
      expect(defaultWalletPirConfigSource(), isNull);
    }
  });
}
