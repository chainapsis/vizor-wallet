import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

const _accountA = 'account-a';
const _accountB = 'account-b';

void main() {
  test('fails closed before an authoritative desktop-open height', () {
    final gate = DesktopOpenMigrationFallbackGate();

    expect(gate.allows(_accountA, _statusWithScheduledHeight(999)), isFalse);
    expect(gate.needsAuthoritativeEntryHeight, isTrue);
    expect(gate.epochEntryHeight, isNull);
  });

  test('allows only one account that was overdue at desktop open', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAccount = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first',
    );
    final secondAccount = _statusWithScheduledHeight(
      1_000,
      scheduledTxid: 'second',
    );
    gate.captureOpenStatus(_accountA, firstAccount);
    gate.captureOpenStatus(_accountB, secondAccount);

    expect(gate.allows(_accountA, firstAccount), isTrue);
    gate.consumeIfOpenOverdue(firstAccount);

    expect(gate.allows(_accountB, secondAccount), isFalse);
  });

  test('does not block a transfer that becomes due after desktop open', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final overdueAtOpen = _statusWithScheduledHeight(999);
    final scheduledAfterOpen = _statusWithScheduledHeight(1_001);
    gate.captureOpenStatus(_accountA, overdueAtOpen);
    gate.captureOpenStatus(_accountB, scheduledAfterOpen);

    gate.consumeIfOpenOverdue(overdueAtOpen);

    expect(gate.allows(_accountB, scheduledAfterOpen), isTrue);
  });

  test('grants a new wallet-global allowance after an epoch restart', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final overdue = _statusWithScheduledHeight(999);
    gate.captureOpenStatus(_accountA, overdue);
    gate.consumeIfOpenOverdue(overdue);
    expect(gate.allows(_accountA, overdue), isFalse);

    gate
      ..restartEpoch()
      ..observeEpochEntryHeight(1_100);
    gate.captureOpenStatus(_accountA, overdue);

    expect(gate.allows(_accountA, overdue), isTrue);
  });

  test('window visibility changes alone do not replenish the allowance', () {
    // Hiding and re-showing the desktop window is not an epoch boundary; only
    // an explicit restart (process suspension or wallet reset) re-arms the
    // one-transfer allowance. The coordinator therefore never notifies the
    // gate about visibility, so a consumed allowance must stay consumed.
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final overdue = _statusWithScheduledHeight(999);
    gate.captureOpenStatus(_accountA, overdue);
    gate.consumeIfOpenOverdue(overdue);

    expect(gate.allows(_accountA, overdue), isFalse);
  });

  test('keeps allowing scheduled transfers that come due while hidden', () {
    // While the desktop process keeps running (hidden or visible), a transfer
    // whose height arrives after the epoch snapshot is a normal scheduled
    // broadcast — it must not depend on the one-transfer open allowance even
    // after that allowance is consumed.
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final overdueAtOpen = _statusWithScheduledHeight(999, scheduledTxid: 'a');
    gate.captureOpenStatus(_accountA, overdueAtOpen);
    gate.consumeIfOpenOverdue(overdueAtOpen);

    final dueWhileHidden = _statusWithScheduledHeight(
      1_050,
      scheduledTxid: 'b',
    );
    gate.captureOpenStatus(_accountB, _statusWithoutScheduledTransfers());
    expect(gate.tryAcquireForAdvance(_accountB, dueWhileHidden), isTrue);
  });

  test('one failing account snapshot blocks only that account', () {
    // Account B's status read keeps failing, so it is never captured. Its own
    // scheduled transfers must stay paused (its overdue-at-open set is
    // unknown), but account A — captured normally — must broadcast on
    // schedule instead of the whole wallet failing closed.
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final capturedAccount = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'captured',
    );
    gate.captureOpenStatus(_accountA, capturedAccount);

    final uncaptured = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'uncaptured',
    );
    expect(gate.allows(_accountA, capturedAccount), isTrue);
    expect(gate.allows(_accountB, uncaptured), isFalse);
    expect(gate.needsOpenStatusSnapshotFor(_accountB), isTrue);

    // The failing account recovers on a later sweep and is captured then;
    // its overdue-at-open transfers join the fallback set mid-epoch.
    gate.captureOpenStatus(_accountB, uncaptured);
    expect(gate.needsOpenStatusSnapshotFor(_accountB), isFalse);
    expect(gate.allows(_accountB, uncaptured), isTrue);
    gate.consumeIfOpenOverdue(uncaptured);
    expect(gate.allows(_accountA, capturedAccount), isFalse);
  });

  test('recapture cannot widen an account snapshot mid-epoch', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    gate.captureOpenStatus(_accountA, _statusWithoutScheduledTransfers());

    // A transfer observed later in the epoch (for example redrawn to a height
    // below the entry tip by a Rust catch-up reschedule) must not be
    // reclassified as overdue-at-open.
    final laterObservation = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'redrawn-low',
    );
    gate.captureOpenStatus(_accountA, laterObservation);

    expect(gate.isOpenOverdue(laterObservation), isFalse);
    expect(gate.allows(_accountA, laterObservation), isTrue);
  });

  test('uses the authoritative tip instead of a stale cached sync height', () {
    const staleCachedHeight = 900;
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAccount = _statusWithScheduledHeight(
      staleCachedHeight + 50,
      scheduledTxid: 'first',
    );
    final secondAccount = _statusWithScheduledHeight(
      staleCachedHeight + 60,
      scheduledTxid: 'second',
    );
    gate.captureOpenStatus(_accountA, firstAccount);
    gate.captureOpenStatus(_accountB, secondAccount);

    expect(gate.allows(_accountA, firstAccount), isTrue);
    gate.consumeIfOpenOverdue(firstAccount);

    expect(gate.allows(_accountB, secondAccount), isFalse);
  });

  test('keeps the original open snapshot through wallet-wide reschedule', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAccount = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first',
    );
    final secondAccount = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'second',
    );
    gate.captureOpenStatus(_accountA, firstAccount);
    gate.captureOpenStatus(_accountB, secondAccount);
    gate.consumeIfOpenOverdue(firstAccount);

    expect(gate.allows(_accountB, secondAccount), isFalse);
    expect(
      gate.allows(
        _accountB,
        _statusWithScheduledHeight(1_001, scheduledTxid: 'second'),
      ),
      isTrue,
    );
  });

  test('central advance acquisition rejects a manual second attempt', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final automatic = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'automatic',
    );
    final manualRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'manual-retry',
    );
    gate.captureOpenStatus(_accountA, automatic);
    gate.captureOpenStatus(_accountB, manualRetry);

    expect(gate.tryAcquireForAdvance(_accountA, automatic), isTrue);
    expect(gate.tryAcquireForAdvance(_accountB, manualRetry), isFalse);
  });

  test('returns an unused reservation after a no-op advance', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatus(_accountA, firstAttempt);
    gate.captureOpenStatus(_accountB, laterRetry);

    expect(gate.tryAcquireForAdvance(_accountA, firstAttempt), isTrue);
    gate.completeAdvance(firstAttempt, _result());

    expect(gate.tryAcquireForAdvance(_accountB, laterRetry), isTrue);
  });

  test('returns a reservation after an advance fails before acceptance', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatus(_accountA, firstAttempt);
    gate.captureOpenStatus(_accountB, laterRetry);

    expect(gate.tryAcquireForAdvance(_accountA, firstAttempt), isTrue);
    gate.failAdvance(firstAttempt);

    expect(gate.tryAcquireForAdvance(_accountB, laterRetry), isTrue);
  });

  test('confirmed transfers do not make a no-op look newly accepted', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
      confirmedTxCount: 1,
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
      confirmedTxCount: 1,
    );
    gate.captureOpenStatus(_accountA, firstAttempt);
    gate.captureOpenStatus(_accountB, laterRetry);

    expect(gate.tryAcquireForAdvance(_accountA, firstAttempt), isTrue);
    gate.completeAdvance(firstAttempt, _result(broadcastedCount: 1));

    expect(gate.tryAcquireForAdvance(_accountB, laterRetry), isTrue);
  });

  test('commits a reservation after a durable broadcast', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatus(_accountA, firstAttempt);
    gate.captureOpenStatus(_accountB, laterRetry);

    expect(gate.tryAcquireForAdvance(_accountA, firstAttempt), isTrue);
    gate.completeAdvance(
      firstAttempt,
      _result(broadcastedCount: 1, txids: 'first-attempt'),
    );

    expect(gate.tryAcquireForAdvance(_accountB, laterRetry), isFalse);
  });

  test('denomination broadcast does not commit the fallback reservation', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeEpochEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'migration-transfer',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatus(_accountA, firstAttempt);
    gate.captureOpenStatus(_accountB, laterRetry);

    expect(gate.tryAcquireForAdvance(_accountA, firstAttempt), isTrue);
    gate.completeAdvance(
      firstAttempt,
      _result(broadcastedCount: 1, txids: 'denomination-stage'),
    );

    expect(gate.tryAcquireForAdvance(_accountB, laterRetry), isTrue);
  });
}

rust_sync.IronwoodMigrationResult _result({
  int broadcastedCount = 0,
  String txids = '',
}) {
  return rust_sync.IronwoodMigrationResult(
    txids: txids,
    status: 'broadcast_scheduled',
    broadcastedCount: broadcastedCount,
    totalCount: 1,
    feeZatoshi: BigInt.zero,
    migratedZatoshi: BigInt.from(100000000),
  );
}

rust_sync.MigrationStatus _statusWithoutScheduledTransfers() {
  return _statusWithScheduledHeight(0, scheduledStatus: 'confirmed');
}

rust_sync.MigrationStatus _statusWithScheduledHeight(
  int scheduledHeight, {
  String scheduledTxid = 'scheduled-tx',
  String scheduledStatus = 'scheduled',
  int broadcastedTxCount = 0,
  int confirmedTxCount = 0,
}) {
  return rust_sync.MigrationStatus(
    phase: 'broadcast_scheduled',
    activeRunId: 'run-1',
    targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 1,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: confirmedTxCount,
    totalCount: 1,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    scheduledBroadcasts: [
      rust_sync.MigrationScheduledBroadcast(
        txidHex: scheduledTxid,
        valueZatoshi: BigInt.from(100000000),
        scheduledAtMs: 0,
        scheduledHeight: scheduledHeight,
        status: scheduledStatus,
      ),
    ],
    parts: const [],
  );
}
