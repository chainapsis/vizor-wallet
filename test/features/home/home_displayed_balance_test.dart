import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/services/home_displayed_balance.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  final sync = SyncState(
    accountUuid: 'account-1',
    hasBalanceData: true,
    displayShieldedBalance: BigInt.from(250),
    displayIronwoodBalance: BigInt.from(40),
    displayIronwoodPendingBalance: BigInt.from(2),
    displayOrchardBalance: BigInt.from(208),
    displayOrchardLockedBalance: BigInt.from(20),
    transparentBalance: BigInt.from(100),
    displayTotalBalance: BigInt.from(370),
  );

  test('is the shielded balance, without transparent or held funds', () {
    expect(homeDisplayedBalance(sync, ironwoodOnly: false), BigInt.from(250));
  });

  test('is the Ironwood pool alone once Home shows only Ironwood', () {
    expect(homeDisplayedBalance(sync, ironwoodOnly: true), BigInt.from(42));
  });
}
