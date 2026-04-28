import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test('pendingBalance is the explicit pending pool sum', () {
    final state = SyncState(
      transparentBalance: BigInt.from(100),
      saplingBalance: BigInt.from(20),
      orchardBalance: BigInt.from(30),
      transparentPendingBalance: BigInt.from(3),
      saplingPendingBalance: BigInt.from(4),
      orchardPendingBalance: BigInt.from(5),
      spendableBalance: BigInt.from(50),
      totalBalance: BigInt.from(162),
    );

    expect(state.pendingBalance, BigInt.from(12));
  });
}
