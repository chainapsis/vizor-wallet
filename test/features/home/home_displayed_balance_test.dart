import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/services/home_displayed_balance.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test('counts every shielded pool, without transparent or held funds', () {
    final sync = SyncState(
      accountUuid: 'account-1',
      hasBalanceData: true,
      saplingBalance: BigInt.from(30),
      saplingPendingBalance: BigInt.from(5),
      orchardBalance: BigInt.from(200),
      orchardPendingBalance: BigInt.from(8),
      orchardLockedBalance: BigInt.from(20),
      ironwoodBalance: BigInt.from(40),
      ironwoodPendingBalance: BigInt.from(2),
      transparentBalance: BigInt.from(100),
      totalBalance: BigInt.from(405),
    );

    expect(homeDisplayedBalance(sync), BigInt.from(285));
  });
}
