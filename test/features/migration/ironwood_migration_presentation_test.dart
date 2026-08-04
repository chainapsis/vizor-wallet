import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/ironwood_migration_presentation.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('formats a private plan as an estimated duration, not block count', () {
    final plan = rust_sync.OrchardMigrationPrivatePlan(
      targetValuesZatoshi: frb.Uint64List.fromList([1_000_000, 2_000_000]),
      totalInputZatoshi: BigInt.from(3_050_000),
      totalMigratableZatoshi: BigInt.from(3_000_000),
      orchardChangeZatoshi: BigInt.zero,
      denominationSplitFeeZatoshi: BigInt.from(20_000),
      migrationFeeZatoshi: BigInt.from(30_000),
      estimatedTotalFeeZatoshi: BigInt.from(50_000),
      plannedBatchCount: 2,
      denominationSplitStageCount: 5,
      denominationSplitLayerCount: 1,
      signingBatchLimit: 16,
      scheduleMeanDelayBlocks: 144,
      scheduleMaxDelayBlocks: 576,
      proofReadinessDelayBlocks: 146,
      scheduledTransfers: [
        rust_sync.MigrationScheduledTransfer(
          partIndex: 0,
          valueZatoshi: BigInt.from(1_000_000),
          blockOffset: 0,
        ),
        rust_sync.MigrationScheduledTransfer(
          partIndex: 1,
          valueZatoshi: BigInt.from(2_000_000),
          blockOffset: 144,
        ),
      ],
    );

    expect(migrationPlanPreparationDelayBlocks(plan), 150);
    expect(migrationPlanCompletionDurationLabel(plan), '~7 hrs');
    expect(migrationBlockOffsetDurationLabel(148), '~4 hrs');
    expect(
      migrationPlanCompletionTimingLabel(plan, now: DateTime(2026, 7, 17, 12)),
      'Jul 17, 18:11',
    );
  });

  test('does not add a mean schedule delay to a single immediate part', () {
    final plan = rust_sync.OrchardMigrationPrivatePlan(
      targetValuesZatoshi: frb.Uint64List.fromList([1_000_000]),
      totalInputZatoshi: BigInt.from(1_030_000),
      totalMigratableZatoshi: BigInt.from(1_000_000),
      orchardChangeZatoshi: BigInt.zero,
      denominationSplitFeeZatoshi: BigInt.zero,
      migrationFeeZatoshi: BigInt.from(30_000),
      estimatedTotalFeeZatoshi: BigInt.from(30_000),
      plannedBatchCount: 1,
      denominationSplitStageCount: 0,
      denominationSplitLayerCount: 0,
      signingBatchLimit: 16,
      scheduleMeanDelayBlocks: 144,
      scheduleMaxDelayBlocks: 576,
      proofReadinessDelayBlocks: 0,
      scheduledTransfers: [
        rust_sync.MigrationScheduledTransfer(
          partIndex: 0,
          valueZatoshi: BigInt.from(1_000_000),
          blockOffset: 0,
        ),
      ],
    );

    expect(migrationPlanCompletionDurationLabel(plan), '~4 mins');
    expect(
      migrationPlanCompletionTimingLabel(plan, now: DateTime(2026, 7, 17, 12)),
      'Jul 17, 12:03',
    );
  });

  test('includes direct-note proof readiness without split layers', () {
    final plan = rust_sync.OrchardMigrationPrivatePlan(
      targetValuesZatoshi: frb.Uint64List.fromList([1_000_000]),
      totalInputZatoshi: BigInt.from(1_030_000),
      totalMigratableZatoshi: BigInt.from(1_000_000),
      orchardChangeZatoshi: BigInt.zero,
      denominationSplitFeeZatoshi: BigInt.zero,
      migrationFeeZatoshi: BigInt.from(30_000),
      estimatedTotalFeeZatoshi: BigInt.from(30_000),
      plannedBatchCount: 1,
      denominationSplitStageCount: 0,
      denominationSplitLayerCount: 0,
      signingBatchLimit: 16,
      scheduleMeanDelayBlocks: 144,
      scheduleMaxDelayBlocks: 576,
      proofReadinessDelayBlocks: 144,
      scheduledTransfers: [
        rust_sync.MigrationScheduledTransfer(
          partIndex: 0,
          valueZatoshi: BigInt.from(1_000_000),
          blockOffset: 0,
        ),
      ],
    );

    expect(migrationPlanPreparationDelayBlocks(plan), 144);
    expect(migrationPlanCompletionDurationLabel(plan), '~4 hrs');
  });

  test('adds later schedule offsets after migration preparation', () {
    expect(
      migrationPlanPartDelayBlocks(
        preparationDelayBlocks: 288,
        scheduleOffsetBlocks: 0,
      ),
      288,
    );
    expect(
      migrationPlanPartDelayBlocks(
        preparationDelayBlocks: 288,
        scheduleOffsetBlocks: 144,
      ),
      432,
    );
    expect(
      migrationPlanPartDelayBlocks(
        preparationDelayBlocks: 288,
        scheduleOffsetBlocks: 288,
      ),
      576,
    );
  });

  test(
    'uses persisted migration transaction status before schedule timing',
    () {
      final now = DateTime(2026, 7, 17, 12);

      expect(
        migrationScheduledBroadcastLabel(
          _broadcast('confirmed', now.subtract(const Duration(hours: 1))),
          now: now,
        ),
        'Confirmed',
      );
      expect(
        migrationScheduledBroadcastLabel(
          _broadcast('broadcasted', now.subtract(const Duration(minutes: 1))),
          now: now,
        ),
        'Submitted',
      );
    },
  );

  test(
    'formats scheduled migration transactions from their actual due time',
    () {
      final now = DateTime(2026, 7, 17, 12);

      expect(
        migrationScheduledBroadcastLabel(
          _broadcast('scheduled', now.add(const Duration(minutes: 3))),
          now: now,
        ),
        'in 3 min',
      );
      expect(
        migrationScheduledBroadcastLabel(
          _broadcast('scheduled', now.add(const Duration(hours: 2))),
          now: now,
          approximate: true,
        ),
        '~in 2 hrs',
      );
      expect(
        migrationScheduledBroadcastLabel(
          _broadcast('scheduled', now.subtract(const Duration(seconds: 1))),
          now: now,
        ),
        'Due now',
      );
    },
  );

  test('summarizes dispatch state without presenting it as completion ETA', () {
    final now = DateTime(2026, 7, 17, 12);
    final confirming = _status(
      phase: 'waiting_migration_confirmations',
      broadcasts: [_broadcast('broadcasted', now)],
    );
    final scheduled = _status(
      phase: 'broadcast_scheduled',
      broadcasts: [
        _broadcast('scheduled', now.add(const Duration(minutes: 3))),
      ],
    );

    expect(migrationDispatchTimingLabel(confirming, now: now), 'Confirming');
    expect(migrationDispatchTimingLabel(scheduled, now: now), 'Jul 17, 12:03');
    expect(
      migrationCompletionTimingLabel(scheduled, abbreviateMonth: false),
      'July 17, 12:03',
    );
    expect(migrationCompletionTimingLabel(confirming), 'Jul 17, 12:00');
  });

  test('estimates a local completion time before schedules are persisted', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: 'ready_to_migrate',
      broadcasts: const [],
      totalCount: 2,
    );

    expect(migrationCompletionTimingLabel(status, now: now), 'Jul 17, 18:00');
  });

  test('estimates live completion from scheduled height, not stored time', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: 'broadcast_scheduled',
      broadcasts: [
        _broadcast(
          'scheduled',
          DateTime(2026, 7, 17, 12, 2),
          scheduledHeight: 1_010,
        ),
        _broadcast(
          'scheduled-latest-height',
          DateTime(2026, 7, 17, 12, 1),
          scheduledHeight: 1_020,
        ),
      ],
    );

    expect(
      migrationCompletionTimingLabel(status, now: now, currentHeight: 1_000),
      'Jul 17, 12:25',
    );
  });

  test('uses the full projected migration height when available', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: 'broadcast_scheduled',
      broadcasts: [_broadcast('scheduled', now, scheduledHeight: 1_010)],
      estimatedCompletionHeight: 1_030,
    );

    expect(
      migrationCompletionTimingLabel(status, now: now, currentHeight: 1_000),
      'Jul 17, 12:37',
    );
  });

  test(
    'keeps an overdue active estimate beyond trusted confirmation depth',
    () {
      final now = DateTime(2026, 7, 17, 12);
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        estimatedCompletionHeight: 999,
        confirmationTarget: 3,
      );

      expect(
        migrationCompletionTimingLabel(status, now: now, currentHeight: 1_000),
        'Jul 17, 12:03',
      );
    },
  );

  test('formats the next migration action in local time', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: 'ready_to_migrate',
      broadcasts: const [],
      nextActionHeight: 1_020,
    );

    expect(
      migrationNextActionTimingLabel(status, currentHeight: 1_000, now: now),
      '~12:25',
    );
  });

  test('does not invent a completion time for an active unprojected run', () {
    final now = DateTime(2026, 7, 17, 12);
    final status = _status(
      phase: 'ready_to_migrate',
      activeRunId: 'run-1',
      broadcasts: const [],
    );

    expect(
      migrationCompletionTimingLabel(status, now: now, currentHeight: 1_000),
      'Schedule pending',
    );
  });

  test(
    'estimates completion while an active schedule is being recalculated',
    () {
      final now = DateTime(2026, 7, 17, 12);
      final status = _status(
        phase: 'broadcast_scheduled',
        activeRunId: 'run-1',
        broadcasts: const [],
        totalCount: 3,
        nextActionHeight: 1_020,
        confirmationTarget: 3,
      );

      expect(
        migrationApproximateCompletionTimingLabel(
          status,
          now: now,
          currentHeight: 1_000,
        ),
        'Jul 17, 18:28',
      );
    },
  );

  test('keeps next-day action labels compact', () {
    final now = DateTime(2026, 7, 17, 23, 50);

    expect(
      migrationHeightTimingLabel(1_020, currentHeight: 1_000, now: now),
      '~Jul 18',
    );
  });

  test('formats remaining migration delay as a duration', () {
    expect(
      migrationHeightRemainingDurationLabel(1_020, currentHeight: 1_000),
      '~in 25 minutes',
    );
    expect(
      migrationHeightRemainingDurationLabel(1_000, currentHeight: 1_000),
      'ready now',
    );
  });

  test('detects a scheduled broadcast as soon as its height is due', () {
    final status = _status(
      phase: 'broadcast_scheduled',
      broadcasts: [
        _broadcast('scheduled', DateTime(2026), scheduledHeight: 1_000),
      ],
    );

    expect(
      migrationHasDueScheduledBroadcast(status, currentHeight: 999),
      isFalse,
    );
    expect(
      migrationHasDueScheduledBroadcast(status, currentHeight: 1_000),
      isTrue,
    );
  });

  test('orders rescheduled parts by their effective chronology', () {
    final ordered = orderedMigrationParts([
      _part(index: 0, scheduleOrder: 0, scheduledHeight: 1_200),
      _part(index: 1, scheduleOrder: 1, scheduledHeight: 1_100),
      _part(index: 2, scheduleOrder: 2),
    ]);

    expect(ordered.map((part) => part.partIndex), [1, 0, 2]);
  });

  test('presents the next scheduled note amount and block', () {
    final status = _status(
      phase: 'broadcast_scheduled',
      broadcasts: const [],
      targetValues: [20_000, 40_000],
      parts: [
        _part(
          index: 0,
          value: 20_000,
          state: rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 3_428_143,
        ),
        _part(
          index: 1,
          value: 40_000,
          state: rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 3_500_000,
        ),
      ],
    );

    final presentation = migrationNextActionPresentation(
      status: status,
      currentHeight: 3_400_000,
    );

    expect(presentation.label, 'Next migration');
    expect(presentation.amountZatoshi, BigInt.from(20_000));
    expect(presentation.detail, 'at');
    expect(presentation.scheduledHeight, 3_428_143);
  });

  test('presents the rebased height for an unpromoted signed note', () {
    final status = _status(
      phase: 'broadcast_scheduled',
      broadcasts: const [],
      nextActionHeight: 3_435_409,
      parts: [
        _part(
          index: 0,
          value: 20_000,
          state: rust_sync.MigrationPartState.preparing,
          scheduledHeight: 3_435_409,
        ),
      ],
    );

    final presentation = migrationNextActionPresentation(
      status: status,
      currentHeight: 3_435_400,
    );

    expect(presentation.label, 'Next migration');
    expect(presentation.amountZatoshi, BigInt.from(20_000));
    expect(presentation.detail, 'at');
    expect(presentation.scheduledHeight, 3_435_409);
  });

  test('presents a scheduled transfer before an internal proof window', () {
    final status = _status(
      phase: 'broadcast_scheduled',
      broadcasts: const [],
      proofReady: false,
      nextProofWindowHeight: 1_074,
      nextProofWindowPartIndices: [2],
      parts: [
        _part(
          index: 0,
          scheduleOrder: 0,
          value: 500_000_000,
          state: rust_sync.MigrationPartState.migrating,
          scheduledHeight: 1_071,
        ),
        _part(
          index: 1,
          scheduleOrder: 1,
          value: 50_000_000_000,
          state: rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 1_083,
        ),
        _part(
          index: 2,
          scheduleOrder: 2,
          value: 1_000_000_000_000,
          scheduledHeight: 1_700,
        ),
      ],
    );

    final presentation = migrationNextActionPresentation(
      status: status,
      currentHeight: 1_071,
    );

    expect(presentation.label, 'Next migration');
    expect(presentation.amountZatoshi, BigInt.from(50_000_000_000));
    expect(presentation.detail, 'at');
    expect(presentation.scheduledHeight, 1_083);
  });

  test('keeps a signing part block while the batch needs input', () {
    final status = _status(
      phase: 'ready_to_migrate',
      broadcasts: const [],
      targetValues: [20_000, 40_000],
      currentSigningPartIndices: [1],
      parts: [
        _part(
          index: 0,
          value: 20_000,
          state: rust_sync.MigrationPartState.scheduled,
          scheduledHeight: 3_428_143,
        ),
        _part(
          index: 1,
          value: 40_000,
          state: rust_sync.MigrationPartState.needsInput,
          scheduledHeight: 3_500_000,
        ),
      ],
    );

    final presentation = migrationNextActionPresentation(
      status: status,
      currentHeight: 3_400_000,
      requiresInput: true,
    );

    expect(presentation.amountZatoshi, BigInt.from(40_000));
    expect(presentation.detail, 'at');
    expect(presentation.scheduledHeight, 3_500_000);
  });

  test('does not count prepared denominations as migrated value', () {
    final status = _status(
      phase: 'ready_to_migrate',
      broadcasts: const [],
      targetValues: [100_000_000, 200_000_000],
      parts: [
        _part(
          index: 0,
          value: 100_000_000,
          state: rust_sync.MigrationPartState.completed,
        ),
        _part(
          index: 1,
          value: 200_000_000,
          state: rust_sync.MigrationPartState.completed,
        ),
      ],
    );

    expect(migrationCompletedValue(status), BigInt.zero);
  });

  group('projectedMigrationPartHeights', () {
    test(
      'projects the approved cadence from the tip when nothing is assigned',
      () {
        final status = _status(
          phase: 'broadcast_scheduled',
          broadcasts: const [],
          totalCount: 4,
          parts: [
            for (var index = 0; index < 4; index++)
              _part(index: index, scheduleOrder: index),
          ],
        );

        expect(
          projectedMigrationPartHeights(status: status, currentHeight: 1_000),
          {0: 1_144, 1: 1_288, 2: 1_432, 3: 1_576},
        );
      },
    );

    test('continues from the last height Rust actually assigned', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 4,
        parts: [
          _part(
            index: 0,
            scheduleOrder: 0,
            state: rust_sync.MigrationPartState.scheduled,
            scheduledHeight: 1_200,
          ),
          _part(
            index: 1,
            scheduleOrder: 1,
            state: rust_sync.MigrationPartState.scheduled,
            scheduledHeight: 1_400,
          ),
          _part(index: 2, scheduleOrder: 2),
          _part(index: 3, scheduleOrder: 3),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 1_000),
        {2: 1_544, 3: 1_688},
      );
    });

    test('never projects a height the chain has already passed', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 2,
        parts: [
          _part(
            index: 0,
            scheduleOrder: 0,
            state: rust_sync.MigrationPartState.completed,
            scheduledHeight: 1_200,
          ),
          _part(index: 1, scheduleOrder: 1),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 5_000),
        {1: 5_144},
      );
    });

    test('follows the schedule order, not the part index', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 3,
        parts: [
          _part(index: 7, scheduleOrder: 2),
          _part(index: 3, scheduleOrder: 0),
          _part(index: 5, scheduleOrder: 1),
        ],
      );

      final projected = projectedMigrationPartHeights(
        status: status,
        currentHeight: 1_000,
      );
      expect(projected, {3: 1_144, 5: 1_288, 7: 1_432});

      final rendered = orderedMigrationParts(
        status.parts,
      ).map((part) => projected[part.partIndex]!).toList();
      expect(rendered, [1_144, 1_288, 1_432]);
      for (var index = 1; index < rendered.length; index++) {
        expect(rendered[index], greaterThan(rendered[index - 1]));
      }
    });

    test('compresses the cadence to land on the estimated completion', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 4,
        confirmationTarget: 10,
        // 1_200 is the last broadcast the estimate implies; the remaining ten
        // blocks are its confirmations.
        estimatedCompletionHeight: 1_210,
        parts: [
          for (var index = 0; index < 4; index++)
            _part(index: index, scheduleOrder: index),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 1_000),
        {0: 1_050, 1: 1_100, 2: 1_150, 3: 1_200},
      );
    });

    test('never lets a compressed cadence tie or go backwards', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 5,
        confirmationTarget: 10,
        estimatedCompletionHeight: 1_012,
        parts: [
          for (var index = 0; index < 5; index++)
            _part(index: index, scheduleOrder: index),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 1_000),
        {0: 1_001, 1: 1_002, 2: 1_003, 3: 1_004, 4: 1_005},
      );
    });

    test('leaves an estimate to the caller when the cadence is unknown', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 2,
        scheduleMeanDelayBlocks: 0,
        parts: [
          _part(index: 0, scheduleOrder: 0),
          _part(index: 1, scheduleOrder: 1),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 1_000),
        isEmpty,
      );
    });

    test('leaves an estimate to the caller when nothing anchors it', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 2,
        parts: [
          _part(index: 0, scheduleOrder: 0),
          _part(index: 1, scheduleOrder: 1),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 0),
        isEmpty,
      );
    });

    test('projects nothing once every part carries a height', () {
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        totalCount: 2,
        parts: [
          _part(
            index: 0,
            scheduleOrder: 0,
            state: rust_sync.MigrationPartState.scheduled,
            scheduledHeight: 1_200,
          ),
          _part(
            index: 1,
            scheduleOrder: 1,
            state: rust_sync.MigrationPartState.scheduled,
            scheduledHeight: 1_400,
          ),
        ],
      );

      expect(
        projectedMigrationPartHeights(status: status, currentHeight: 1_000),
        isEmpty,
      );
    });
  });

  group('migrationPartWaitingWindowHeight', () {
    test('returns the window only for preparing parts assigned to it', () {
      final waiting = _part(index: 1);
      final other = _part(index: 2);
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        parts: [waiting, other],
        nextProofWindowHeight: 4_224_935,
        nextProofWindowPartIndices: const [1],
        proofReady: false,
      );

      expect(
        migrationPartWaitingWindowHeight(status: status, part: waiting),
        4_224_935,
      );
      expect(
        migrationPartWaitingWindowHeight(status: status, part: other),
        isNull,
      );
    });

    test('does not report a window once proofs are ready', () {
      final part = _part(index: 1);
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        parts: [part],
        nextProofWindowHeight: 4_224_935,
        nextProofWindowPartIndices: const [1],
        proofReady: true,
      );

      expect(
        migrationPartWaitingWindowHeight(status: status, part: part),
        isNull,
      );
    });

    test('does not report a window without an applicable proof action', () {
      final part = _part(index: 1);
      final status = _status(
        phase: 'waiting_confirmations',
        broadcasts: const [],
        parts: [part],
        nextProofWindowHeight: 4_224_935,
        nextProofWindowPartIndices: const [1],
      );

      expect(
        migrationPartWaitingWindowHeight(status: status, part: part),
        isNull,
      );
    });

    test('does not treat a projected broadcast height as a window', () {
      final part = _part(index: 1, scheduledHeight: 4_225_079);
      final status = _status(
        phase: 'broadcast_scheduled',
        broadcasts: const [],
        parts: [part],
        proofReady: false,
      );

      expect(
        migrationPartWaitingWindowHeight(status: status, part: part),
        isNull,
      );
    });
  });
}

rust_sync.MigrationScheduledBroadcast _broadcast(
  String status,
  DateTime scheduledAt, {
  int scheduledHeight = 1_000,
}) {
  return rust_sync.MigrationScheduledBroadcast(
    txidHex: status,
    valueZatoshi: BigInt.from(10_000_000),
    scheduledAtMs: scheduledAt.millisecondsSinceEpoch,
    scheduledHeight: scheduledHeight,
    status: status,
  );
}

rust_sync.MigrationStatus _status({
  required String phase,
  required List<rust_sync.MigrationScheduledBroadcast> broadcasts,
  List<int> targetValues = const [],
  List<rust_sync.MigrationPartStatus> parts = const [],
  List<int>? currentSigningPartIndices,
  int? totalCount,
  int? nextActionHeight,
  int? nextProofWindowHeight,
  List<int>? nextProofWindowPartIndices,
  bool? proofReady,
  int? estimatedCompletionHeight,
  int confirmationTarget = 0,
  int scheduleMeanDelayBlocks = 144,
  String? activeRunId,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(targetValues),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: confirmationTarget,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: totalCount ?? broadcasts.length,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: scheduleMeanDelayBlocks,
    scheduleMaxDelayBlocks: 576,
    nextActionHeight: nextActionHeight,
    nextProofWindowHeight: nextProofWindowHeight,
    nextProofWindowPartIndices: nextProofWindowPartIndices == null
        ? null
        : frb.Uint32List.fromList(nextProofWindowPartIndices),
    proofReady: proofReady,
    estimatedCompletionHeight: estimatedCompletionHeight,
    scheduledBroadcasts: broadcasts,
    currentSigningPartIndices: currentSigningPartIndices == null
        ? null
        : frb.Uint32List.fromList(currentSigningPartIndices),
    parts: parts,
  );
}

rust_sync.MigrationPartStatus _part({
  required int index,
  int? scheduleOrder,
  int value = 10_000,
  rust_sync.MigrationPartState state = rust_sync.MigrationPartState.preparing,
  int? scheduledHeight,
}) {
  return rust_sync.MigrationPartStatus(
    partIndex: index,
    scheduleOrder: scheduleOrder,
    valueZatoshi: BigInt.from(value),
    state: state,
    scheduledHeight: scheduledHeight,
    confirmationCount: 0,
    confirmationTarget: 10,
  );
}
