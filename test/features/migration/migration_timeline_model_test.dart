import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_timeline_model.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

rust_sync.MigrationStatus _status({
  String phase = 'ready_to_migrate',
  int pendingTxCount = 0,
  int broadcastedTxCount = 0,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 3,
    pendingTxCount: pendingTxCount,
    signedChildPcztCount: 0,
    pendingPrepTxCount: 0,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: 0,
    totalCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: const [],
  );
}

MigrationTimelineModel _map(
  MigrationViewState viewState, {
  rust_sync.MigrationStatus? status,
  bool runInFlight = false,
  MigrationRunIntent intent = MigrationRunIntent.none,
  bool sendNeedsScan = false,
}) {
  return migrationTimelineModel(
    viewState: viewState,
    status: status,
    runInFlight: runInFlight,
    intent: intent,
    sendNeedsScan: sendNeedsScan,
  );
}

void main() {
  test('in-flight intent wins over provider-derived state', () {
    final preparing = _map(
      MigrationViewState.planningDenominations,
      runInFlight: true,
      intent: MigrationRunIntent.preparing,
    );
    expect(preparing.split, MigrationNodeStatus.active);
    expect(preparing.confirm, MigrationNodeStatus.pending);
    expect(preparing.send, MigrationNodeStatus.pending);

    final migrating = _map(
      MigrationViewState.readyToMigrate,
      runInFlight: true,
      intent: MigrationRunIntent.migrating,
    );
    expect(migrating.split, MigrationNodeStatus.done);
    expect(migrating.send, MigrationNodeStatus.active);
  });

  test('prepare/confirm phases advance the first two nodes', () {
    final preparing = _map(MigrationViewState.preparingDenominations);
    expect(preparing.split, MigrationNodeStatus.active);
    expect(preparing.send, MigrationNodeStatus.pending);

    final confirming = _map(MigrationViewState.waitingDenomConfirmations);
    expect(confirming.split, MigrationNodeStatus.done);
    expect(confirming.confirm, MigrationNodeStatus.active);
    expect(confirming.send, MigrationNodeStatus.pending);
  });

  test('send-stage phases mark split+confirm done and send active', () {
    for (final phase in [
      MigrationViewState.readyToMigrate,
      MigrationViewState.buildingSigningBatch,
      MigrationViewState.signingBatch,
      MigrationViewState.broadcastScheduled,
      MigrationViewState.broadcasting,
      MigrationViewState.waitingMigrationConfirmations,
      MigrationViewState.paused,
    ]) {
      final m = _map(phase);
      expect(m.split, MigrationNodeStatus.done, reason: '$phase');
      expect(m.confirm, MigrationNodeStatus.done, reason: '$phase');
      expect(m.send, MigrationNodeStatus.active, reason: '$phase');
    }
  });

  test('sendNeedsScan only flows through send-active states', () {
    expect(
      _map(
        MigrationViewState.readyToMigrate,
        sendNeedsScan: true,
      ).sendNeedsScan,
      isTrue,
    );
    expect(
      _map(
        MigrationViewState.waitingDenomConfirmations,
        sendNeedsScan: true,
      ).sendNeedsScan,
      isFalse,
    );
  });

  test('paused migrations expose a resume action', () {
    final m = _map(MigrationViewState.paused);
    expect(m.split, MigrationNodeStatus.done);
    expect(m.confirm, MigrationNodeStatus.done);
    expect(m.send, MigrationNodeStatus.active);
    expect(m.sendCanResume, isTrue);
    expect(m.sendNeedsScan, isFalse);
  });

  test('complete marks all nodes done', () {
    final m = _map(MigrationViewState.complete);
    expect(m.split, MigrationNodeStatus.done);
    expect(m.confirm, MigrationNodeStatus.done);
    expect(m.send, MigrationNodeStatus.done);
  });

  test('failedRecoverable routes the error to the failing node', () {
    final beforeSend = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable'),
    );
    expect(beforeSend.split, MigrationNodeStatus.error);
    expect(beforeSend.send, MigrationNodeStatus.pending);

    final afterSend = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', broadcastedTxCount: 1),
    );
    expect(afterSend.split, MigrationNodeStatus.done);
    expect(afterSend.send, MigrationNodeStatus.error);
  });

  test('terminal phases are send errors', () {
    expect(
      _map(MigrationViewState.failedTerminal).send,
      MigrationNodeStatus.error,
    );
    expect(_map(MigrationViewState.abandoned).send, MigrationNodeStatus.error);
  });
}
