import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_failover_provider.dart';
import 'sync_provider.dart';

typedef NetworkUpgradeWindowGetter =
    rust_wallet.NetworkUpgradeWindow? Function({
      required String network,
      required BigInt tipHeight,
    });

final networkUpgradeWindowGetterProvider = Provider<NetworkUpgradeWindowGetter>(
  (_) => rust_wallet.getNetworkUpgradeWindow,
);

class NetworkUpgradeWindowState {
  const NetworkUpgradeWindowState({
    this.nextActivationHeight,
    this.holdsTransactions = false,
  });

  static const none = NetworkUpgradeWindowState();

  final int? nextActivationHeight;

  /// Whether transactions are refused for the last few blocks before the
  /// upgrade: their capped expiry would be too close for nodes to accept.
  final bool holdsTransactions;
}

/// [window] applied at [tipHeight]. The hold ends once the next block is on
/// the new branch.
NetworkUpgradeWindowState networkUpgradeWindowAt(
  rust_wallet.NetworkUpgradeWindow? window,
  int tipHeight,
) {
  if (window == null) return NetworkUpgradeWindowState.none;
  final next = window.nextActivationHeight.toInt();
  return NetworkUpgradeWindowState(
    nextActivationHeight: next,
    holdsTransactions:
        tipHeight >= window.sendHoldFromTip.toInt() && tipHeight + 1 < next,
  );
}

/// The next network upgrade as the wallet's chain tip sees it. Rust refuses
/// held work itself; screens read this to stop before side effects Rust
/// cannot undo, such as a swap opened for a deposit that cannot be sent.
final networkUpgradeWindowProvider = Provider<NetworkUpgradeWindowState>((ref) {
  final network = ref.watch(
    rpcEndpointFailoverProvider.select((state) => state.current.networkName),
  );
  final tipHeight = ref.watch(
    syncProvider.select((sync) {
      final state = sync.value;
      return state == null
          ? 0
          : math.max(state.chainTipHeight, state.scannedHeight);
    }),
  );
  if (tipHeight <= 0) return NetworkUpgradeWindowState.none;
  try {
    return networkUpgradeWindowAt(
      ref.watch(networkUpgradeWindowGetterProvider)(
        network: network,
        tipHeight: BigInt.from(tipHeight),
      ),
      tipHeight,
    );
  } catch (error) {
    // Rust still refuses held work; this only loses the early stop.
    log('NetworkUpgradeWindow: unavailable: $error');
    return NetworkUpgradeWindowState.none;
  }
});
