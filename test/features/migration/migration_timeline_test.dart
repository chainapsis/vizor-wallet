import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_timeline_model.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/features/migration/widgets/migration_timeline.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

Future<void> _pump(
  WidgetTester tester,
  MigrationTimelineModel model, {
  rust_sync.MigrationStatus? status,
  int totalShares = 3,
  List<rust_sync.TransactionInfo> shares = const [],
  DateTime? now,
  VoidCallback? onScanSends,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: SingleChildScrollView(
            child: MigrationTimeline(
              model: model,
              status: status,
              shares: shares,
              amountZatoshi: BigInt.from(120000000),
              totalShares: totalShares,
              now: now ?? DateTime.fromMillisecondsSinceEpoch(0),
              onScanSends: onScanSends,
              onRetry: onRetry,
            ),
          ),
        ),
      ),
    ),
  );
}

rust_sync.MigrationStatus _status({
  List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts = const [],
  String phase = 'broadcast_scheduled',
  int denominationSplitCompletedCount = 0,
  int denominationSplitTotalCount = 0,
  int denominationConfirmationCount = 3,
  int denominationConfirmationTarget = 3,
  int confirmedTxCount = 0,
  int? totalCount,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationSplitCompletedCount: denominationSplitCompletedCount,
    denominationSplitTotalCount: denominationSplitTotalCount,
    denominationConfirmationCount: denominationConfirmationCount,
    denominationConfirmationTarget: denominationConfirmationTarget,
    pendingTxCount: scheduledBroadcasts.length,
    signedChildPcztCount: 0,
    pendingPrepTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: confirmedTxCount,
    totalCount: totalCount ?? scheduledBroadcasts.length,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: scheduledBroadcasts,
  );
}

void main() {
  testWidgets('renders the three node titles', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
      ),
    );
    expect(find.text(MigrationCopy.splitTitle), findsOneWidget);
    expect(find.text(MigrationCopy.confirmTitle(0)), findsOneWidget);
    expect(find.text(MigrationCopy.sendTitle), findsOneWidget);
  });

  testWidgets('shows completed, remaining, and current confirmation round', (
    tester,
  ) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.active,
        send: MigrationNodeStatus.pending,
      ),
      status: _status(
        phase: 'waiting_denom_confirmations',
        denominationSplitCompletedCount: 1,
        denominationSplitTotalCount: 3,
        denominationConfirmationCount: 2,
        totalCount: 30,
      ),
    );

    expect(find.text('3 split transactions prepared'), findsOneWidget);
    expect(find.text('Done · 30 standard notes'), findsNothing);
    expect(find.text(MigrationCopy.confirmTitle(3)), findsOneWidget);
    expect(
      find.text('1 of 3 splits complete · 2 splits remaining'),
      findsOneWidget,
    );
    expect(
      find.text('Current confirmation round · 2 of 3 confirmations'),
      findsOneWidget,
    );
  });

  testWidgets('uses singular split copy for a one-stage split', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.active,
        send: MigrationNodeStatus.pending,
      ),
      status: _status(
        phase: 'waiting_denom_confirmations',
        denominationSplitTotalCount: 1,
        denominationConfirmationCount: 0,
        totalCount: 30,
      ),
    );

    expect(find.text('1 split transaction prepared'), findsOneWidget);
    expect(find.text(MigrationCopy.confirmTitle(1)), findsOneWidget);
    expect(
      find.text('0 of 1 split complete · 1 split remaining'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to confirmation depth when split total is unknown', (
    tester,
  ) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.active,
        send: MigrationNodeStatus.pending,
      ),
      status: _status(
        phase: 'waiting_denom_confirmations',
        denominationConfirmationCount: 1,
      ),
    );

    expect(
      find.text('Current confirmation round · 1 of 3 confirmations'),
      findsOneWidget,
    );
    expect(find.text('No splits needed'), findsNothing);
  });

  testWidgets('keeps the completed split count visible during submissions', (
    tester,
  ) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
      ),
      status: _status(
        denominationSplitCompletedCount: 3,
        denominationSplitTotalCount: 3,
        totalCount: 30,
      ),
    );

    expect(find.text('Done · 30 standard notes'), findsOneWidget);
    expect(find.text('3 of 3 splits complete'), findsOneWidget);
  });

  testWidgets('staged fallback shows the scan action', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
        sendNeedsScan: true,
      ),
      onScanSends: () {},
    );
    expect(find.text(MigrationCopy.sendScanCta), findsOneWidget);
  });

  testWidgets('paused migration shows the resume action', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
        sendCanResume: true,
      ),
      onRetry: () {},
    );
    expect(find.text(MigrationCopy.sendResumeCta), findsOneWidget);
  });

  testWidgets('only the next scheduled share row shows a countdown', (
    tester,
  ) async {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
      ),
      status: _status(
        scheduledBroadcasts: const [
          rust_sync.MigrationScheduledBroadcast(
            txidHex:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            scheduledAtMs: 61000,
            status: 'scheduled',
          ),
          rust_sync.MigrationScheduledBroadcast(
            txidHex:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            scheduledAtMs: 121000,
            status: 'scheduled',
          ),
        ],
      ),
      totalShares: 2,
      now: now,
    );

    expect(
      find.text(
        MigrationCopy.shareScheduledIn(
          migrationCountdownLabel(const Duration(seconds: 60)),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        MigrationCopy.shareScheduledIn(
          migrationCountdownLabel(const Duration(seconds: 120)),
        ),
      ),
      findsNothing,
    );
    expect(find.text(MigrationCopy.shareScheduled), findsOneWidget);
  });

  testWidgets('uses durable run status for confirmed submission progress', (
    tester,
  ) async {
    const firstTxid =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const secondTxid =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
      ),
      status: _status(
        phase: 'waiting_migration_confirmations',
        scheduledBroadcasts: const [
          rust_sync.MigrationScheduledBroadcast(
            txidHex: firstTxid,
            scheduledAtMs: 1,
            status: 'confirmed',
          ),
          rust_sync.MigrationScheduledBroadcast(
            txidHex: secondTxid,
            scheduledAtMs: 2,
            status: 'confirmed',
          ),
        ],
        confirmedTxCount: 2,
        totalCount: 30,
      ),
      totalShares: 30,
      shares: [
        rust_sync.TransactionInfo(
          txidHex: firstTxid,
          minedHeight: BigInt.zero,
          expiredUnmined: false,
          accountBalanceDelta: 0,
          fee: BigInt.zero,
          blockTime: BigInt.zero,
          isTransparent: false,
          txKind: 'migration',
          displayAmount: BigInt.one,
          displayPool: 'ironwood',
          createdTime: BigInt.zero,
        ),
      ],
    );

    expect(find.text('2 of 30 confirmed'), findsOneWidget);
    expect(find.text(MigrationCopy.shareConfirmed), findsNWidgets(3));
  });
}
