import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/network_upgrade_window_provider.dart';
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

void main() {
  final window = rust_wallet.NetworkUpgradeWindow(
    nextActivationHeight: BigInt.from(1000),
    sendHoldFromTip: BigInt.from(996),
  );

  bool holdsAt(int tip) =>
      networkUpgradeWindowAt(window, tip).holdsTransactions;

  test('holds transactions until the next block upgrades', () {
    expect(holdsAt(995), isFalse);
    expect(holdsAt(996), isTrue);
    expect(holdsAt(998), isTrue);
    // The next block is on the new branch.
    expect(holdsAt(999), isFalse);
    expect(networkUpgradeWindowAt(window, 997).nextActivationHeight, 1000);
  });

  test('no scheduled upgrade holds nothing', () {
    final state = networkUpgradeWindowAt(null, 997);
    expect(state.holdsTransactions, isFalse);
    expect(state.nextActivationHeight, isNull);
  });
}
