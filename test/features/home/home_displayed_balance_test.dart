import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/services/home_displayed_balance.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  final sync = SyncState(
    accountUuid: 'account-1',
    hasBalanceData: true,
    // 30 Sapling + 5 pending, 200 Orchard + 8 pending, 40 Ironwood + 2
    // pending, 20 Orchard locked by the migration.
    displayShieldedBalance: BigInt.from(285),
    displayIronwoodBalance: BigInt.from(40),
    displayIronwoodPendingBalance: BigInt.from(2),
    displayOrchardBalance: BigInt.from(200),
    displayOrchardPendingBalance: BigInt.from(8),
    displayOrchardLockedBalance: BigInt.from(20),
    transparentBalance: BigInt.from(100),
    displayTotalBalance: BigInt.from(405),
  );

  test('is the shielded balance, without transparent or held funds', () {
    expect(homeDisplayedBalance(sync, ironwoodOnly: false), BigInt.from(285));
  });

  test('leaves out migrating Orchard but keeps Sapling during a migration', () {
    expect(homeDisplayedBalance(sync, ironwoodOnly: true), BigInt.from(77));
  });

  test('is the Ironwood pool alone for an account without Sapling', () {
    final noSapling = SyncState(
      accountUuid: 'account-1',
      hasBalanceData: true,
      displayIronwoodBalance: BigInt.from(40),
      displayIronwoodPendingBalance: BigInt.from(2),
      displayOrchardBalance: BigInt.from(200),
      displayShieldedBalance: BigInt.from(242),
    );
    expect(
      homeDisplayedBalance(noSapling, ironwoodOnly: true),
      BigInt.from(42),
    );
  });
}
