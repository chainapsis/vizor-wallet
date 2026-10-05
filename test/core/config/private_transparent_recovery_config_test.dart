import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/private_transparent_recovery_config.dart';

void main() {
  test('private transparent recovery is opt-in by default', () {
    expect(kZcashPrivateTransparentRecovery, isFalse);
  });
}
