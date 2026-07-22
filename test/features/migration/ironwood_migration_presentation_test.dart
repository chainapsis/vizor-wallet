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
      denominationSplitStageCount: 1,
      signingBatchLimit: 16,
      scheduleMeanDelayBlocks: 144,
      scheduleMaxDelayBlocks: 576,
      maxPreparedNotesPerRun: 64,
      scheduledTransfers: [
        rust_sync.MigrationScheduledTransfer(
          partIndex: 0,
          valueZatoshi: BigInt.from(1_000_000),
          blockOffset: 144,
        ),
        rust_sync.MigrationScheduledTransfer(
          partIndex: 1,
          valueZatoshi: BigInt.from(2_000_000),
          blockOffset: 288,
        ),
      ],
    );

    expect(migrationPlanCompletionDurationLabel(plan), '~7 hrs');
    expect(migrationBlockOffsetDurationLabel(148), '~4 hrs');
    expect(
      migrationPlanCompletionTimingLabel(plan, now: DateTime(2026, 7, 17, 12)),
      'Jul 17, 18:05',
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
      'soon',
    );
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
  int? totalCount,
  int? nextActionHeight,
  int? estimatedCompletionHeight,
  int confirmationTarget = 0,
  String? activeRunId,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List(0),
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
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    nextActionHeight: nextActionHeight,
    estimatedCompletionHeight: estimatedCompletionHeight,
    scheduledBroadcasts: broadcasts,
    parts: const [],
  );
}
