import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_step_state.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

rust_sync.MigrationStatus _status({
  String phase = 'ready_to_migrate',
  int pendingTxCount = 0,
  int signedChildPcztCount = 0,
  int denominationConfirmationCount = 0,
  int broadcastedTxCount = 0,
  int confirmedTxCount = 0,
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: denominationConfirmationCount,
    denominationConfirmationTarget: 3,
    pendingTxCount: pendingTxCount,
    signedChildPcztCount: signedChildPcztCount,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: confirmedTxCount,
    totalCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(60),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: scheduledBroadcasts,
  );
}

MigrationStepsModel _map(
  MigrationViewState viewState, {
  rust_sync.MigrationStatus? status,
  bool runInFlight = false,
  MigrationRunIntent intent = MigrationRunIntent.none,
}) {
  return migrationStepsModel(
    viewState: viewState,
    status: status,
    runInFlight: runInFlight,
    intent: intent,
  );
}

void main() {
  test('in-flight intent wins over provider-derived state', () {
    final preparing = _map(
      MigrationViewState.planningDenominations,
      runInFlight: true,
      intent: MigrationRunIntent.preparing,
    );
    expect(preparing.stepOne, MigrationStepOneState.running);
    expect(preparing.stepTwo, MigrationStepTwoState.locked);

    final migrating = _map(
      MigrationViewState.readyToMigrate,
      runInFlight: true,
      intent: MigrationRunIntent.migrating,
    );
    expect(migrating.stepOne, MigrationStepOneState.done);
    expect(migrating.stepTwo, MigrationStepTwoState.running);
  });

  test('balance-derived phases map to step one states', () {
    expect(
      _map(MigrationViewState.noOrchardFunds).stepOne,
      MigrationStepOneState.blocked,
    );
    expect(
      _map(MigrationViewState.waitingForSpendableOrchard).stepOne,
      MigrationStepOneState.blocked,
    );
    expect(
      _map(MigrationViewState.planningDenominations).stepOne,
      MigrationStepOneState.active,
    );
    expect(
      _map(MigrationViewState.preparingDenominations).stepOne,
      MigrationStepOneState.running,
    );
    expect(
      _map(MigrationViewState.waitingDenomConfirmations).stepOne,
      MigrationStepOneState.waiting,
    );
    expect(
      _map(MigrationViewState.planningDenominations).stepTwo,
      MigrationStepTwoState.locked,
    );
  });

  test('run phases map to step two states with step one done', () {
    final ready = _map(MigrationViewState.readyToMigrate);
    expect(ready.stepOne, MigrationStepOneState.done);
    expect(ready.stepTwo, MigrationStepTwoState.ready);

    final readyWithSignedChildren = _map(
      MigrationViewState.readyToMigrate,
      status: _status(signedChildPcztCount: 4),
    );
    expect(readyWithSignedChildren.stepOne, MigrationStepOneState.done);
    expect(readyWithSignedChildren.stepTwo, MigrationStepTwoState.running);

    expect(
      _map(MigrationViewState.paused).stepTwo,
      MigrationStepTwoState.ready,
    );

    for (final running in [
      MigrationViewState.buildingSigningBatch,
      MigrationViewState.signingBatch,
      MigrationViewState.broadcastScheduled,
      MigrationViewState.broadcasting,
    ]) {
      expect(_map(running).stepOne, MigrationStepOneState.done);
      expect(_map(running).stepTwo, MigrationStepTwoState.running);
    }

    expect(
      _map(MigrationViewState.waitingMigrationConfirmations).stepTwo,
      MigrationStepTwoState.confirming,
    );
    expect(
      _map(MigrationViewState.complete).stepTwo,
      MigrationStepTwoState.done,
    );
  });

  test('failedRecoverable routes to the step that actually failed', () {
    final beforeMigrationTxs = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable'),
    );
    expect(beforeMigrationTxs.stepOne, MigrationStepOneState.error);
    expect(beforeMigrationTxs.stepTwo, MigrationStepTwoState.locked);

    final withPending = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', pendingTxCount: 3),
    );
    expect(withPending.stepOne, MigrationStepOneState.done);
    expect(withPending.stepTwo, MigrationStepTwoState.error);

    final withBroadcasted = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', broadcastedTxCount: 1),
    );
    expect(withBroadcasted.stepTwo, MigrationStepTwoState.error);
  });

  test('terminal phases are step two errors', () {
    expect(
      _map(MigrationViewState.failedTerminal).stepTwo,
      MigrationStepTwoState.error,
    );
    expect(
      _map(MigrationViewState.abandoned).stepTwo,
      MigrationStepTwoState.error,
    );
  });

  test('migration broadcast helpers distinguish due and confirming work', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1_000);
    final futureScheduled = _status(
      phase: 'broadcast_scheduled',
      scheduledBroadcasts: const [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'future',
          scheduledAtMs: 2_000,
          status: 'scheduled',
        ),
      ],
    );
    expect(migrationHasScheduledPendingBroadcasts(futureScheduled), isTrue);
    expect(migrationHasDueScheduledBroadcast(futureScheduled, now), isFalse);
    expect(
      migrationHasBroadcastedUnconfirmedTransactions(futureScheduled),
      isFalse,
    );

    final dueScheduled = _status(
      phase: 'broadcast_scheduled',
      scheduledBroadcasts: const [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'due',
          scheduledAtMs: 1_000,
          status: 'scheduled',
        ),
      ],
    );
    expect(migrationHasDueScheduledBroadcast(dueScheduled, now), isTrue);

    final broadcasted = _status(
      phase: 'waiting_migration_confirmations',
      broadcastedTxCount: 1,
      scheduledBroadcasts: const [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'submitted',
          scheduledAtMs: 500,
          status: 'broadcasted',
        ),
      ],
    );
    expect(migrationHasScheduledPendingBroadcasts(broadcasted), isFalse);
    expect(migrationHasDueScheduledBroadcast(broadcasted, now), isFalse);
    expect(migrationHasBroadcastedUnconfirmedTransactions(broadcasted), isTrue);

    final confirmed = _status(
      phase: 'broadcast_scheduled',
      confirmedTxCount: 1,
    );
    expect(migrationHasBroadcastedUnconfirmedTransactions(confirmed), isFalse);
  });

  test('signed child helpers wait for denomination readiness', () {
    final waitingForConfirmations = _status(
      phase: 'waiting_denom_confirmations',
      signedChildPcztCount: 4,
      denominationConfirmationCount: 2,
    );
    expect(migrationHasSignedChildPczts(waitingForConfirmations), isTrue);
    expect(
      migrationSignedChildrenMayFinalize(waitingForConfirmations),
      isFalse,
    );

    final confirmedDenominations = _status(
      phase: 'waiting_denom_confirmations',
      signedChildPcztCount: 4,
      denominationConfirmationCount: 3,
    );
    expect(migrationSignedChildrenMayFinalize(confirmedDenominations), isTrue);

    final ready = _status(phase: 'ready_to_migrate', signedChildPcztCount: 4);
    expect(migrationSignedChildrenMayFinalize(ready), isTrue);

    final noSignedChildren = _status(
      phase: 'ready_to_migrate',
      signedChildPcztCount: 0,
    );
    expect(migrationSignedChildrenMayFinalize(noSignedChildren), isFalse);
  });

  test('migration countdown label expands for hours and days', () {
    expect(migrationCountdownLabel(const Duration(seconds: 42)), '42s');
    expect(
      migrationCountdownLabel(const Duration(minutes: 12, seconds: 3)),
      '12m 3s',
    );
    expect(
      migrationCountdownLabel(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1h 2m 3s',
    );
    expect(
      migrationCountdownLabel(
        const Duration(days: 1, hours: 2, minutes: 3, seconds: 4),
      ),
      '1d 2h 3m 4s',
    );
  });

  test('migration close warning uses scheduled and confirming work', () {
    final now = DateTime.fromMillisecondsSinceEpoch(10_000);
    final scheduled = _status(
      phase: 'broadcast_scheduled',
      scheduledBroadcasts: const [
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'first',
          scheduledAtMs: 12_000,
          status: 'scheduled',
        ),
        rust_sync.MigrationScheduledBroadcast(
          txidHex: 'last',
          scheduledAtMs: 15_000,
          status: 'scheduled',
        ),
      ],
    );

    expect(migrationShouldWarnBeforeClose(scheduled), isTrue);
    expect(
      migrationRemainingScheduledSubmissionTime(scheduled, now),
      const Duration(seconds: 5),
    );

    final confirming = _status(
      phase: 'waiting_migration_confirmations',
      broadcastedTxCount: 1,
    );
    expect(migrationShouldWarnBeforeClose(confirming), isTrue);
    expect(migrationRemainingScheduledSubmissionTime(confirming, now), isNull);

    expect(
      migrationShouldWarnBeforeClose(_status(phase: 'building_signing_batch')),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeClose(_status(phase: 'signing_batch')),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeClose(
        _status(phase: 'ready_to_migrate', signedChildPcztCount: 1),
      ),
      isTrue,
    );

    final complete = _status(phase: 'complete', confirmedTxCount: 2);
    expect(migrationShouldWarnBeforeClose(complete), isFalse);
    expect(migrationRemainingScheduledSubmissionTime(complete, now), isNull);
  });
}
