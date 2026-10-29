import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/network_upgrade_hold.dart';

void main() {
  test('maps the send hold refusal to the hold copy', () {
    expect(
      networkUpgradeHoldMessage(
        StateError(
          "Transactions can't be sent this close to the network upgrade. "
          'Try again after it activates.',
        ),
      ),
      kNetworkUpgradeHoldMessage,
    );
  });

  test('leaves other errors to the caller', () {
    expect(networkUpgradeHoldMessage(StateError('proposal not found')), isNull);
  });
}
