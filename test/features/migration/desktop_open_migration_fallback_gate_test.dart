import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('throttles a failed reconciliation attempt', () async {
    var now = DateTime(2026, 7, 30);
    final throttle = MigrationReconciliationAttemptThrottle(
      interval: const Duration(seconds: 30),
      now: () => now,
    );

    expect(throttle.shouldAttempt('account-1', 'progress-1'), isTrue);
    await expectLater(
      throttle.run<void>(
        'account-1',
        'progress-1',
        () async => throw StateError('lightwalletd unavailable'),
      ),
      throwsStateError,
    );

    expect(throttle.shouldAttempt('account-1', 'progress-1'), isFalse);
    expect(throttle.shouldAttempt('account-1', 'progress-2'), isTrue);

    now = now.add(const Duration(seconds: 30));
    expect(throttle.shouldAttempt('account-1', 'progress-1'), isTrue);
  });

  test('coalesces reconciliation and waits for an account advance', () async {
    final gate = MigrationReconciliationOperationGate();
    final releaseAdvance = Completer<void>();
    final reconciliationStarted = Completer<void>();
    var reconciliationCount = 0;

    Future<void> reconcile() async {
      reconciliationCount++;
      reconciliationStarted.complete();
    }

    final first = gate.run(
      'account-1',
      activeAdvance: () => releaseAdvance.future,
      reconcile: reconcile,
    );
    final duplicate = gate.run(
      'account-1',
      activeAdvance: () => null,
      reconcile: reconcile,
    );
    await Future<void>.delayed(Duration.zero);
    expect(reconciliationCount, 0);

    releaseAdvance.complete();
    await reconciliationStarted.future;
    await Future.wait([first, duplicate]);

    expect(reconciliationCount, 1);
    expect(gate.operationFor('account-1'), isNull);
  });

  test('account advance can wait for reconciliation to finish', () async {
    final gate = MigrationReconciliationOperationGate();
    final reconciliationStarted = Completer<void>();
    final releaseReconciliation = Completer<void>();
    var advanceStarted = false;

    final reconciliation = gate.run(
      'account-1',
      activeAdvance: () => null,
      reconcile: () async {
        reconciliationStarted.complete();
        await releaseReconciliation.future;
      },
    );
    await reconciliationStarted.future;

    final advance = () async {
      await gate.waitFor('account-1');
      advanceStarted = true;
    }();
    await Future<void>.delayed(Duration.zero);
    expect(advanceStarted, isFalse);

    releaseReconciliation.complete();
    await Future.wait([reconciliation, advance]);

    expect(advanceStarted, isTrue);
  });

  test('fails closed before an authoritative desktop-open height', () {
    final gate = DesktopOpenMigrationFallbackGate();

    expect(gate.allows(_statusWithScheduledHeight(999)), isFalse);
    expect(gate.needsAuthoritativeEntryHeight, isTrue);
  });

  test('allows only one account that was overdue at desktop open', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAccount = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first',
    );
    final secondAccount = _statusWithScheduledHeight(
      1_000,
      scheduledTxid: 'second',
    );
    gate.captureOpenStatuses([firstAccount, secondAccount]);

    expect(gate.allows(firstAccount), isTrue);
    gate.consumeIfOpenOverdue(firstAccount);

    expect(gate.allows(secondAccount), isFalse);
  });

  test('does not block a transfer that becomes due after desktop open', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final overdueAtOpen = _statusWithScheduledHeight(999);
    final scheduledAfterOpen = _statusWithScheduledHeight(1_001);
    gate.captureOpenStatuses([overdueAtOpen, scheduledAfterOpen]);

    gate.consumeIfOpenOverdue(overdueAtOpen);

    expect(gate.allows(scheduledAfterOpen), isTrue);
  });

  test('grants a new wallet-global allowance after the next foreground', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final overdue = _statusWithScheduledHeight(999);
    gate.captureOpenStatuses([overdue]);
    gate.consumeIfOpenOverdue(overdue);
    expect(gate.allows(overdue), isFalse);

    gate
      ..leaveForeground()
      ..enterForeground()
      ..observeForegroundEntryHeight(1_100);
    gate.captureOpenStatuses([overdue]);

    expect(gate.allows(overdue), isTrue);
  });

  test('duplicate foreground notification does not replenish allowance', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final overdue = _statusWithScheduledHeight(999);
    gate.captureOpenStatuses([overdue]);
    gate.consumeIfOpenOverdue(overdue);

    gate.enterForeground();

    expect(gate.allows(overdue), isFalse);
  });

  test('uses the authoritative tip instead of a stale cached sync height', () {
    const staleCachedHeight = 900;
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAccount = _statusWithScheduledHeight(
      staleCachedHeight + 50,
      scheduledTxid: 'first',
    );
    final secondAccount = _statusWithScheduledHeight(
      staleCachedHeight + 60,
      scheduledTxid: 'second',
    );
    gate.captureOpenStatuses([firstAccount, secondAccount]);

    expect(gate.allows(firstAccount), isTrue);
    gate.consumeIfOpenOverdue(firstAccount);

    expect(gate.allows(secondAccount), isFalse);
  });

  test('keeps the original open snapshot through wallet-wide reschedule', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAccount = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first',
    );
    final secondAccount = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'second',
    );
    gate.captureOpenStatuses([firstAccount, secondAccount]);
    gate.consumeIfOpenOverdue(firstAccount);

    expect(gate.allows(secondAccount), isFalse);
    expect(
      gate.allows(_statusWithScheduledHeight(1_001, scheduledTxid: 'second')),
      isTrue,
    );
  });

  test('central advance acquisition rejects a manual second attempt', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final automatic = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'automatic',
    );
    final manualRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'manual-retry',
    );
    gate.captureOpenStatuses([automatic, manualRetry]);

    expect(gate.tryAcquireForAdvance(automatic), isTrue);
    expect(gate.tryAcquireForAdvance(manualRetry), isFalse);
  });

  test('returns an unused reservation after a no-op advance', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatuses([firstAttempt, laterRetry]);

    expect(gate.tryAcquireForAdvance(firstAttempt), isTrue);
    gate.completeAdvance(firstAttempt, _result());

    expect(gate.tryAcquireForAdvance(laterRetry), isTrue);
  });

  test('returns a reservation after an advance fails before acceptance', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatuses([firstAttempt, laterRetry]);

    expect(gate.tryAcquireForAdvance(firstAttempt), isTrue);
    gate.failAdvance(firstAttempt);

    expect(gate.tryAcquireForAdvance(laterRetry), isTrue);
  });

  test('confirmed transfers do not make a no-op look newly accepted', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
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
    gate.captureOpenStatuses([firstAttempt, laterRetry]);

    expect(gate.tryAcquireForAdvance(firstAttempt), isTrue);
    gate.completeAdvance(firstAttempt, _result(broadcastedCount: 1));

    expect(gate.tryAcquireForAdvance(laterRetry), isTrue);
  });

  test('commits a reservation after a durable broadcast', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'first-attempt',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatuses([firstAttempt, laterRetry]);

    expect(gate.tryAcquireForAdvance(firstAttempt), isTrue);
    gate.completeAdvance(
      firstAttempt,
      _result(broadcastedCount: 1, txids: 'first-attempt'),
    );

    expect(gate.tryAcquireForAdvance(laterRetry), isFalse);
  });

  test('commits a reservation after rebroadcasting a needs-resign tx', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final recovered = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'recovered',
      broadcastStatus: 'needs_resign',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatuses([recovered, laterRetry]);

    expect(gate.tryAcquireForAdvance(recovered), isTrue);
    gate.completeAdvance(
      recovered,
      _result(broadcastedCount: 1, txids: 'recovered'),
    );

    expect(gate.tryAcquireForAdvance(laterRetry), isFalse);
  });

  test('denomination broadcast does not commit the fallback reservation', () {
    final gate = DesktopOpenMigrationFallbackGate()
      ..observeForegroundEntryHeight(1_000);
    final firstAttempt = _statusWithScheduledHeight(
      999,
      scheduledTxid: 'migration-transfer',
    );
    final laterRetry = _statusWithScheduledHeight(
      998,
      scheduledTxid: 'later-retry',
    );
    gate.captureOpenStatuses([firstAttempt, laterRetry]);

    expect(gate.tryAcquireForAdvance(firstAttempt), isTrue);
    gate.completeAdvance(
      firstAttempt,
      _result(broadcastedCount: 1, txids: 'denomination-stage'),
    );

    expect(gate.tryAcquireForAdvance(laterRetry), isTrue);
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

rust_sync.MigrationStatus _statusWithScheduledHeight(
  int scheduledHeight, {
  String scheduledTxid = 'scheduled-tx',
  String broadcastStatus = 'scheduled',
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
        status: broadcastStatus,
      ),
    ],
    parts: const [],
  );
}
