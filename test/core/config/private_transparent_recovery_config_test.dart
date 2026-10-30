import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/private_transparent_recovery_config.dart';

void main() {
  test('private queries always describes transparent recovery', () {
    expect(
      kPrivateQueriesSettingsCopy,
      'Experimental. Recovers transparent funds privately, preventing the '
      'server from learning your transparent addresses. Looks up supported '
      'transactions without revealing their IDs to servers.',
    );
  });
}
