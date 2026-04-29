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

  test('displayPercentage defaults to actual percentage', () {
    final state = SyncState(percentage: 0.25);

    expect(state.percentage, 0.25);
    expect(state.displayPercentage, 0.25);
  });

  test(
    'displayPercentage can advance independently from actual percentage',
    () {
      final state = SyncState(percentage: 0.25);
      final displayed = state.copyWith(displayPercentage: 0.30);

      expect(displayed.percentage, 0.25);
      expect(displayed.displayPercentage, 0.30);
    },
  );

  test('displayPercentage can be reset below a previous display value', () {
    final state = SyncState(percentage: 0.30, displayPercentage: 0.50);
    final reset = state.copyWith(percentage: 0.25, displayPercentage: 0.25);

    expect(reset.percentage, 0.25);
    expect(reset.displayPercentage, 0.25);
  });
}
