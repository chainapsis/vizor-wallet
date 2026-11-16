import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/zcash/spendable_wait.dart';
import '../features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'account_provider.dart';
import 'block_spacing_provider.dart';
import 'sync_provider.dart';

/// Whether [sync] carries a balance the waits can be read from, and whether
/// it is a completed balance held through a catch-up.
///
/// A settled balance qualifies, and so does a completed one the tip has
/// moved past: each new block leaves the balance one block behind until a
/// sync that started from the completed one catches up, and dropping the
/// wait for that would blink every surface. A first scan, a restore and a
/// failed sync state nothing.
({bool readable, bool catchingUp}) _waitSource(SyncState sync) {
  if (!sync.hasBalanceData || sync.failure != null || sync.error != null) {
    return (readable: false, catchingUp: false);
  }
  if (sync.hasSettledSpendableBalance) {
    return (readable: true, catchingUp: false);
  }
  final heldFromCompleted =
      sync.isSyncComplete || sync.startedFromCompletedSync;
  return (readable: heldFromCompleted, catchingUp: heldFromCompleted);
}

int _waitTip(SyncState sync) =>
    math.max(sync.scannedHeight, sync.chainTipHeight);

/// Shielded funds [accountUuid] holds but cannot spend yet, and when they
/// can be spent.
///
/// Null unless the balance is settled at the tip or held through a catch-up
/// from a settled one, so a balance still being scanned is never read as a
/// confirmation wait. Also null while a migration limits sends to Ironwood,
/// where the pools are not interchangeable.
final spendableWaitProvider = Provider.autoDispose
    .family<SpendableWait?, String?>((ref, accountUuid) {
      if (accountUuid == null) return null;
      final sync = ref.watch(
        syncProvider.select(
          (value) => (value.value ?? SyncState()).scopedToAccount(accountUuid),
        ),
      );
      final source = _waitSource(sync);
      if (!source.readable) return null;
      final migration = ref.watch(ironwoodHomeMigrationPresentationProvider);
      if (migration.mode == IronwoodHomeMigrationCtaMode.resume &&
          migration.accountUuid == accountUuid) {
        return null;
      }
      return resolveSpendableWait(
        availableNow: sync.spendableBalance,
        shieldedPending:
            sync.saplingPendingBalance +
            sync.orchardPendingBalance +
            sync.ironwoodPendingBalance,
        changePending: sync.changePendingConfirmation,
        tipHeight: _waitTip(sync),
        spacing: ref.watch(blockSpacingProvider),
        transactions: sync.recentTransactions,
        catchingUp: source.catchingUp,
      );
    });

/// The chain position activity rows measure a receipt's wait from. Null
/// unless [accountUuid] has received funds waiting with a stated wait, so a
/// row never promises a wait the balance does not show.
final receivedSpendableWaitClockProvider = Provider.autoDispose
    .family<SpendableWaitClock?, String?>((ref, accountUuid) {
      final wait = ref.watch(spendableWaitProvider(accountUuid));
      if (wait == null ||
          wait.receivedWaiting == BigInt.zero ||
          wait.receivedWait == null) {
        return null;
      }
      final position = ref.watch(
        syncProvider.select((value) {
          final sync = (value.value ?? SyncState()).scopedToAccount(
            accountUuid,
          );
          return (_waitTip(sync), _waitSource(sync).catchingUp);
        }),
      );
      return (
        tipHeight: position.$1,
        spacing: ref.watch(blockSpacingProvider),
        catchingUp: position.$2,
      );
    });

final activeReceivedSpendableWaitClockProvider =
    Provider.autoDispose<SpendableWaitClock?>((ref) {
      final accountUuid = ref.watch(
        accountProvider.select((value) => value.value?.activeAccountUuid),
      );
      return ref.watch(receivedSpendableWaitClockProvider(accountUuid));
    });
