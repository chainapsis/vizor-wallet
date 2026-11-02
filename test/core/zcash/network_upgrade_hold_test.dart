import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/network_upgrade_hold.dart';

void main() {
  test('maps both upgrade hold refusals to the hold copy', () {
    for (final refusal in [
      "Migrations can't start this close to the network upgrade. "
          'Try again after it activates.',
      "Transactions can't be sent this close to the network upgrade. "
          'Try again after it activates.',
    ]) {
      expect(
        networkUpgradeHoldMessage(StateError(refusal)),
        kNetworkUpgradeHoldMessage,
      );
    }
  });

  test('maps a schedule drawn before the upgrade to the review copy', () {
    expect(
      networkUpgradeHoldMessage(
        Exception(
          'Migration schedule was drawn before the network upgrade; '
          'review the plan again',
        ),
      ),
      kNetworkUpgradeScheduleChangedMessage,
    );
  });

  test('leaves other errors to the caller', () {
    expect(networkUpgradeHoldMessage(StateError('proposal not found')), isNull);
    expect(
      networkUpgradeHoldMessage(
        'The network upgrade stopped this migration. '
        "Transactions signed before the upgrade can't be sent after it.",
      ),
      isNull,
    );
  });
}
