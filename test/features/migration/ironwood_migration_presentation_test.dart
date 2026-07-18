import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/ironwood_migration_presentation.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
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
}

rust_sync.MigrationScheduledBroadcast _broadcast(
  String status,
  DateTime scheduledAt,
) {
  return rust_sync.MigrationScheduledBroadcast(
    txidHex: status,
    valueZatoshi: BigInt.from(10_000_000),
    scheduledAtMs: scheduledAt.millisecondsSinceEpoch,
    scheduledHeight: 1_000,
    status: status,
  );
}

rust_sync.MigrationStatus _status({
  required String phase,
  required List<rust_sync.MigrationScheduledBroadcast> broadcasts,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: frb.Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: broadcasts.length,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 50,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: broadcasts,
  );
}
