import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/zcash/block_spacing.dart';
import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_failover_provider.dart';
import 'sync_provider.dart';

typedef BlockSpacingScheduleGetter =
    rust_wallet.BlockSpacingSchedule Function({required String network});

final blockSpacingScheduleGetterProvider = Provider<BlockSpacingScheduleGetter>(
  (_) => rust_wallet.getBlockSpacingSchedule,
);

/// Block spacing of the current network, for wall-clock estimates.
final blockSpacingProvider = Provider<BlockSpacing>((ref) {
  try {
    final network = ref.watch(
      rpcEndpointFailoverProvider.select((state) => state.current.networkName),
    );
    final schedule = ref.watch(blockSpacingScheduleGetterProvider)(
      network: network,
    );
    return BlockSpacing(
      nu7ActivationHeight: schedule.nu7ActivationHeight?.toInt(),
      preNu7BlockSeconds: schedule.preNu7BlockSeconds,
      nu7BlockSeconds: schedule.nu7BlockSeconds,
    );
  } catch (error) {
    // Estimates only: keep the pre-NU7 spacing rather than failing the screen.
    log('BlockSpacing: schedule unavailable, using pre-NU7 spacing: $error');
    return BlockSpacing.preNu7;
  }
});

/// Whether the wallet's tip has reached NU7, read as
/// `networkUpgradeWindowProvider` reads the tip.
final nu7ActiveAtWalletTipProvider = Provider<bool>((ref) {
  final activation = ref.watch(
    blockSpacingProvider.select((spacing) => spacing.nu7ActivationHeight),
  );
  if (activation == null) return false;
  final tipHeight = ref.watch(
    syncProvider.select((sync) {
      final state = sync.value;
      return state == null
          ? 0
          : math.max(state.chainTipHeight, state.scannedHeight);
    }),
  );
  return tipHeight >= activation;
});
