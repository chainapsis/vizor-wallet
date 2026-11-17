import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/zcash/block_spacing.dart';
import '../core/zcash/spendable_wait.dart';
import '../features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../rust/api/sync.dart' as rust_sync;
import 'account_provider.dart';
import 'block_spacing_provider.dart';
import 'sync_provider.dart';

typedef _Waiting = ({
  BigInt availableNow,
  List<rust_sync.PendingSpendableEntry> entries,
  int tipHeight,
  BlockSpacing spacing,
});

/// [accountUuid]'s spendable balance with the funds the wallet reported as
/// waiting on confirmations in the same balance read.
///
/// Null without a balance read this session, and after a failed sync, whose
/// block counts no longer run down. Also null while a migration limits sends
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
        entries: sync.pendingSpendable,
        tipHeight: math.max(sync.scannedHeight, sync.chainTipHeight),
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
    entries: sync.entries,
    tipHeight: sync.tipHeight,
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
        entries: waiting.entries,
        tipHeight: waiting.tipHeight,
        spacing: waiting.spacing,
      );
    });

/// [accountUuid]'s mined receipts that cannot be spent yet, by transaction id.
final receivedSpendableWaitsProvider = Provider.autoDispose
    .family<Map<String, ReceivedSpendableWait>, String?>((ref, accountUuid) {
      final waiting = ref.watch(_waitingProvider(accountUuid));
      if (waiting == null) return const {};
      return receivedSpendableWaits(
        entries: waiting.entries,
        tipHeight: waiting.tipHeight,
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
