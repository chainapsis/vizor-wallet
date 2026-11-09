import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/network_upgrade_hold.dart';
import '../../support/test_l10n.dart';

void main() {
  test('maps both upgrade hold refusals to the hold copy', () {
    for (final refusal in [
      "Migrations can't start this close to the network upgrade. "
          'Try again after it activates.',
      "Transactions can't be sent this close to the network upgrade. "
          'Try again after it activates.',
    ]) {
      expect(
        networkUpgradeHoldMessage(testL10n, StateError(refusal)),
        networkUpgradeHoldText(testL10n),
      );
    }
  });

  test('maps a schedule drawn before the upgrade to the review copy', () {
    expect(
      networkUpgradeHoldMessage(
        testL10n,
        Exception(
          'Migration schedule was drawn before the network upgrade; '
          'review the plan again',
        ),
      ),
      testL10n.sendPaymentRequestCheckUpgradeScheduleChanged,
    );
  });

  test('leaves other errors to the caller', () {
    expect(
      networkUpgradeHoldMessage(testL10n, StateError('proposal not found')),
      isNull,
    );
    expect(
      networkUpgradeHoldMessage(
        testL10n,
        'The network upgrade stopped this migration. '
        "Transactions signed before the upgrade can't be sent after it.",
      ),
      isNull,
    );
  });
}
