import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/zcash/block_spacing.dart';
import '../core/zcash/spendable_wait.dart';
import '../features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'account_provider.dart';
import 'block_spacing_provider.dart';
import 'sync_provider.dart';

typedef _Waiting = ({
  BigInt availableNow,
  PendingSpendable pending,
  int scannedHeight,
  BlockSpacing spacing,
});

/// [accountUuid]'s spendable balance with the funds the wallet reported as
/// waiting on confirmations in the same balance read.
///
/// Null without a balance read this session, and after a failed sync, which
/// no longer follows the chain tip the waits are counted to. Also null while a migration limits sends
/// to Ironwood, where the pools are not interchangeable.
final _waitingProvider = Provider.autoDispose.family<_Waiting?, String?>((
  ref,
  accountUuid,
) {
  if (accountUuid == null) return null;
  final sync = ref.watch(
    syncProvider.select((value) {
      final sync = (value.value ?? SyncState()).scopedToAccount(accountUuid);
      return (
        readable:
            sync.hasBalanceData && sync.failure == null && sync.error == null,
        availableNow: sync.spendableBalance,
        pending: sync.pendingSpendable,
        scannedHeight: sync.scannedHeight,
      );
    }),
  );
  if (!sync.readable) return null;
  final migration = ref.watch(ironwoodHomeMigrationPresentationProvider);
  if (migration.mode == IronwoodHomeMigrationCtaMode.resume &&
      migration.accountUuid == accountUuid) {
    return null;
  }
  return (
    availableNow: sync.availableNow,
    pending: sync.pending,
    scannedHeight: sync.scannedHeight,
    spacing: ref.watch(blockSpacingProvider),
  );
});

/// Shielded funds [accountUuid] holds but cannot spend yet, and when they
/// can be spent.
final spendableWaitProvider = Provider.autoDispose
    .family<SpendableWait?, String?>((ref, accountUuid) {
      final waiting = ref.watch(_waitingProvider(accountUuid));
      if (waiting == null) return null;
      return spendableWaitOf(
        availableNow: waiting.availableNow,
        pending: waiting.pending,
        scannedHeight: waiting.scannedHeight,
        spacing: waiting.spacing,
      );
    });

/// [accountUuid]'s mined receipts that cannot be spent yet, by transaction id.
final receivedSpendableWaitsProvider = Provider.autoDispose
    .family<Map<String, ReceivedSpendableWait>, String?>((ref, accountUuid) {
      final waiting = ref.watch(_waitingProvider(accountUuid));
      if (waiting == null) return const {};
      return receivedSpendableWaits(
        pending: waiting.pending,
        scannedHeight: waiting.scannedHeight,
        spacing: waiting.spacing,
      );
    });

final activeReceivedSpendableWaitsProvider =
    Provider.autoDispose<Map<String, ReceivedSpendableWait>>((ref) {
      final accountUuid = ref.watch(
        accountProvider.select((value) => value.value?.activeAccountUuid),
      );
      return ref.watch(receivedSpendableWaitsProvider(accountUuid));
    });
