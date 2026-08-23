import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/voting/voting_state.dart';

void main() {
  test('voting state distinguishes Keystone and Ledger hardware accounts', () {
    final keystone = VotingSessionState(
      roundId: 'round-1',
      isHardwareAccount: true,
      hardwareSignerKind: HardwareSignerKind.keystone,
    );
    final ledger = VotingSessionState(
      roundId: 'round-1',
      isHardwareAccount: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
    );

    expect(keystone.isKeystoneAccount, isTrue);
    expect(keystone.isLedgerAccount, isFalse);
    expect(ledger.isKeystoneAccount, isFalse);
    expect(ledger.isLedgerAccount, isTrue);
    expect(ledger.canSkipRemainingKeystoneBundles, isFalse);
  });
}
