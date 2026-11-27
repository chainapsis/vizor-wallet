import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/services/home_displayed_balance.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  // 30 Sapling + 5 pending, 200 Orchard + 8 pending, 20 Orchard locked by the
  // migration, 40 Ironwood + 2 pending, 100 transparent.
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

  test('counts every shielded pool, without transparent or held funds', () {
    expect(
      homeDisplayedBalance(
        sync,
        IronwoodHomeBalancePresentationMode.allShielded,
      ),
      BigInt.from(285),
    );
  });

  test('is the Orchard to move while a migration is required', () {
    expect(
      homeDisplayedBalance(
        sync,
        IronwoodHomeBalancePresentationMode.orchardOnly,
      ),
      BigInt.from(208),
    );
  });

  test('leaves out migrating Orchard but keeps Sapling once it starts', () {
    expect(
      homeDisplayedBalance(
        sync,
        IronwoodHomeBalancePresentationMode.ironwoodAndSapling,
      ),
      BigInt.from(77),
    );
  });
}
