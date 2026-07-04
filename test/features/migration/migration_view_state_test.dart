import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('account with Orchard funds plans denominations', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.planningDenominations,
    );
  });

  test('preparing run in flight keeps split progress visible', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
        preparingInFlight: true,
      ),
      MigrationViewState.preparingDenominations,
    );
  });

  test('migrating run in flight keeps send progress visible', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
        migratingInFlight: true,
      ),
      MigrationViewState.buildingSigningBatch,
    );
  });

  test('entry card is hidden while progress is settling', () {
    expect(
      migrationShouldShowEntry(
        viewState: MigrationViewState.planningDenominations,
        keepsProgressVisible: false,
      ),
      isTrue,
    );
    expect(
      migrationShouldShowEntry(
        viewState: MigrationViewState.planningDenominations,
        keepsProgressVisible: true,
      ),
      isFalse,
    );
  });

  test('entry CTA is enabled from the ready migration state', () {
    expect(
      migrationCanStartFromEntry(MigrationViewState.planningDenominations),
      isTrue,
    );
    expect(
      migrationCanStartFromEntry(MigrationViewState.noOrchardFunds),
      isFalse,
    );
    expect(
      migrationCanStartFromEntry(MigrationViewState.waitingForSpendableOrchard),
      isFalse,
    );
  });

  test('idle migration amount ignores historical migration transactions', () {
    expect(
      migrationDisplayAmount(
        viewState: MigrationViewState.noOrchardFunds,
        orchardAmount: BigInt.zero,
        migrationTransactionAmounts: [BigInt.from(100)],
      ),
      BigInt.zero,
    );
    expect(
      migrationDisplayAmount(
        viewState: MigrationViewState.planningDenominations,
        orchardAmount: BigInt.from(42),
        migrationTransactionAmounts: [BigInt.from(100)],
      ),
      BigInt.from(42),
    );
  });

  test('active migration amount uses current migration transactions', () {
    expect(
      migrationDisplayAmount(
        viewState: MigrationViewState.waitingMigrationConfirmations,
        orchardAmount: BigInt.zero,
        migrationTransactionAmounts: [BigInt.from(40), BigInt.from(2)],
      ),
      BigInt.from(42),
    );
  });

  test('account with a pending migration shows confirmation wait', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: true,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.waitingMigrationConfirmations,
    );
  });

  test('account with a mined migration shows complete', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: true,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test('account with migrated ironwood balance shows complete', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test('account with remaining orchard funds stays idle after completion', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: true,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.planningDenominations,
    );
  });

  test('account with no orchard or ironwood funds shows no-op', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.noOrchardFunds,
    );
  });

  test('rust phase mapping covers explicit migration phases', () {
    expect(
      migrationViewStateFromRustPhase('waiting_for_spendable_orchard'),
      MigrationViewState.waitingForSpendableOrchard,
    );
    expect(
      migrationViewStateFromRustPhase('ready_to_prepare'),
      MigrationViewState.planningDenominations,
    );
    expect(
      migrationViewStateFromRustPhase('broadcast_scheduled'),
      MigrationViewState.broadcastScheduled,
    );
    expect(
      migrationViewStateFromRustPhase('failed_terminal'),
      MigrationViewState.failedTerminal,
    );
  });

  test('migration txid matching accepts reversed byte order', () {
    const broadcastOrder =
        '24fccdf39b619967ac5904743cb0f4a33b0b4d4b67b84dcee0f4ba0dc2887725';
    const historyOrder =
        '257788c20dbaf4e0ce4db8674b4d0b3ba3f4b03c740459ac6799619bf3cdfc24';

    expect(migrationTxidsMatch(historyOrder, broadcastOrder), isTrue);
  });

  test('migration first transaction index accepts reversed txid order', () {
    const firstBroadcastTxid =
        '24fccdf39b619967ac5904743cb0f4a33b0b4d4b67b84dcee0f4ba0dc2887725';
    const firstHistoryTxid =
        '257788c20dbaf4e0ce4db8674b4d0b3ba3f4b03c740459ac6799619bf3cdfc24';

    expect(
      migrationFirstTransactionIndex(
        transactionTxids: [
          '617b461a369552df0cda9c1764dadb542e240acc433de17660fc20bc0328bf81',
          firstHistoryTxid,
        ],
        firstTxid: firstBroadcastTxid,
      ),
      1,
    );
  });

  test('keep-open warning predicate covers progress-capable phases', () {
    const warnedStates = {
      MigrationViewState.preparingDenominations,
      MigrationViewState.waitingDenomConfirmations,
      MigrationViewState.readyToMigrate,
      MigrationViewState.buildingSigningBatch,
      MigrationViewState.signingBatch,
      MigrationViewState.broadcastScheduled,
      MigrationViewState.broadcasting,
      MigrationViewState.waitingMigrationConfirmations,
    };

    for (final state in MigrationViewState.values) {
      expect(
        state.needsKeepOpenWarning,
        warnedStates.contains(state),
        reason: '$state',
      );
    }
  });

  test('migration txid matching rejects invalid and unrelated txids', () {
    const txid =
        '24fccdf39b619967ac5904743cb0f4a33b0b4d4b67b84dcee0f4ba0dc2887725';
    const unrelated =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    expect(migrationTxidsMatch(txid, 'not-a-txid'), isFalse);
    expect(migrationTxidsMatch(txid, unrelated), isFalse);
  });

  test(
    'software auto-advance fires only at ready_to_migrate, software, idle',
    () {
      rust_sync.MigrationStatus ready({int signedChildren = 0}) =>
          rust_sync.MigrationStatus(
            phase: 'ready_to_migrate',
            targetValuesZatoshi: Uint64List(0),
            preparedNoteCount: 0,
            denominationConfirmationCount: 3,
            denominationConfirmationTarget: 3,
            pendingTxCount: 0,
            signedChildPcztCount: signedChildren,
            pendingPrepTxCount: 0,
            broadcastedTxCount: 0,
            confirmedTxCount: 0,
            totalCount: 4,
            canAbandon: false,
            signingBatchLimit: 8,
            broadcastWindowSeconds: BigInt.from(180),
            maxPreparedNotesPerRun: 64,
            scheduledBroadcasts: const [],
          );

      expect(
        migrationShouldAutoAdvanceSoftware(
          status: ready(),
          isHardware: false,
          runInFlight: false,
          alreadyAttempted: false,
        ),
        isTrue,
      );
      // hardware excluded
      expect(
        migrationShouldAutoAdvanceSoftware(
          status: ready(),
          isHardware: true,
          runInFlight: false,
          alreadyAttempted: false,
        ),
        isFalse,
      );
      // presigned children present -> not the software path
      expect(
        migrationShouldAutoAdvanceSoftware(
          status: ready(signedChildren: 4),
          isHardware: false,
          runInFlight: false,
          alreadyAttempted: false,
        ),
        isFalse,
      );
      // already attempted / in flight -> no re-fire
      expect(
        migrationShouldAutoAdvanceSoftware(
          status: ready(),
          isHardware: false,
          runInFlight: true,
          alreadyAttempted: false,
        ),
        isFalse,
      );
      expect(
        migrationShouldAutoAdvanceSoftware(
          status: ready(),
          isHardware: false,
          runInFlight: false,
          alreadyAttempted: true,
        ),
        isFalse,
      );
    },
  );

  test('keep-open warnings show only while migration needs attention', () {
    rust_sync.MigrationStatus status({
      required String phase,
      int pendingPrepTxCount = 0,
      int signedChildPcztCount = 0,
      int broadcastedTxCount = 0,
      List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts =
          const [],
    }) => rust_sync.MigrationStatus(
      phase: phase,
      targetValuesZatoshi: Uint64List(0),
      preparedNoteCount: 0,
      denominationConfirmationCount: 3,
      denominationConfirmationTarget: 3,
      pendingTxCount: 0,
      signedChildPcztCount: signedChildPcztCount,
      pendingPrepTxCount: pendingPrepTxCount,
      broadcastedTxCount: broadcastedTxCount,
      confirmedTxCount: 0,
      totalCount: 4,
      canAbandon: false,
      signingBatchLimit: 8,
      broadcastWindowSeconds: BigInt.from(180),
      maxPreparedNotesPerRun: 64,
      scheduledBroadcasts: scheduledBroadcasts,
    );

    expect(
      migrationShouldShowGlobalWarning(status(phase: 'ready_to_prepare')),
      isFalse,
    );
    expect(
      migrationShouldWarnBeforeClose(status(phase: 'ready_to_prepare')),
      isFalse,
    );
    expect(
      migrationShouldShowGlobalWarning(
        status(phase: 'waiting_denom_confirmations'),
      ),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeClose(
        status(phase: 'waiting_denom_confirmations'),
      ),
      isTrue,
    );
    expect(
      migrationShouldShowGlobalWarning(status(phase: 'ready_to_migrate')),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeClose(status(phase: 'ready_to_migrate')),
      isTrue,
    );
    expect(
      migrationShouldShowGlobalWarning(status(phase: 'building_signing_batch')),
      isTrue,
    );
    expect(
      migrationShouldShowGlobalWarning(
        status(phase: 'waiting_migration_confirmations'),
      ),
      isTrue,
    );
    expect(
      migrationShouldShowGlobalWarning(
        status(phase: 'ready_to_migrate', signedChildPcztCount: 1),
      ),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeCloseRead(statusKnown: false, status: null),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeCloseRead(statusKnown: true, status: null),
      isFalse,
    );
    expect(
      migrationShouldWarnBeforeCloseSnapshot(
        statusKnown: true,
        status: null,
        keepsProgressVisible: true,
      ),
      isTrue,
    );
    expect(
      migrationShouldWarnBeforeCloseSnapshot(
        statusKnown: true,
        status: null,
        keepsProgressVisible: false,
      ),
      isFalse,
    );
  });

  test('single-QR oversize error is detected for the staged fallback', () {
    expect(
      migrationIsSingleQrTooLargeError(
        'Single Keystone migration signing supports at most 34 migration notes, '
        'but this plan needs 50. Reduce the migration amount or use the staged flow.',
      ),
      isTrue,
    );
    expect(
      migrationIsSingleQrTooLargeError('insufficient spendable funds'),
      isFalse,
    );
  });

  test(
    'staged-fallback Send awaits a scan only before children are signed',
    () {
      rust_sync.MigrationStatus status({int signedChildren = 0}) =>
          rust_sync.MigrationStatus(
            phase: 'ready_to_migrate',
            targetValuesZatoshi: Uint64List(0),
            preparedNoteCount: 0,
            denominationConfirmationCount: 3,
            denominationConfirmationTarget: 3,
            pendingTxCount: 0,
            signedChildPcztCount: signedChildren,
            pendingPrepTxCount: 0,
            broadcastedTxCount: 0,
            confirmedTxCount: 0,
            totalCount: 40,
            canAbandon: false,
            signingBatchLimit: 8,
            broadcastWindowSeconds: BigInt.from(180),
            maxPreparedNotesPerRun: 64,
            scheduledBroadcasts: const [],
          );

      expect(
        timelineSendIsAwaitingScan(MigrationViewState.readyToMigrate, status()),
        isTrue,
      );
      expect(
        timelineSendIsAwaitingScan(
          MigrationViewState.readyToMigrate,
          status(signedChildren: 0),
        ),
        isTrue,
      );
      expect(
        timelineSendIsAwaitingScan(
          MigrationViewState.readyToMigrate,
          status(signedChildren: 40),
        ),
        isFalse,
      );
      expect(
        timelineSendIsAwaitingScan(MigrationViewState.broadcasting, status()),
        isFalse,
      );
    },
  );
}
