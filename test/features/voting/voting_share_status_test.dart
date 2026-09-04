import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/voting_share_status.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_share_status_card.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

void main() {
  test('summarizes confirmed vote shares', () {
    final summary = VotingShareStatusSummary.fromRecords([
      _share(0, confirmed: true),
      _share(1),
      _share(2),
    ]);

    expect(summary.totalCount, 3);
    expect(summary.confirmedCount, 1);
    expect(summary.pendingCount, 2);
    expect(summary.allConfirmed, isFalse);
    expect(summary.confirmedFraction, closeTo(1 / 3, 0.0001));
    expect(summary.latestPendingDueAtSeconds, BigInt.from(1_777_000_002));
    expect(summary.usesStaggeredSubmission, isTrue);
  });

  test('formats the last pending share in minutes, hours, or days', () {
    final now = DateTime.utc(2026, 8, 25, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

    VotingShareStatusSummary summaryAfter(Duration duration) {
      return VotingShareStatusSummary.fromRecords([
        _share(0, submitAt: BigInt.from(nowSeconds + duration.inSeconds)),
      ]);
    }

    expect(
      votingShareCompletionEstimateText(
        summaryAfter(const Duration(seconds: 30)),
        now: now,
      ),
      'Complete in about 1 minute',
    );
    expect(
      votingShareCompletionEstimateText(
        summaryAfter(const Duration(minutes: 17, seconds: 20)),
        now: now,
      ),
      'Complete in about 17 minutes',
    );
    expect(
      votingShareCompletionEstimateText(
        summaryAfter(const Duration(hours: 2, minutes: 20)),
        now: now,
      ),
      'Complete in about 2 hours',
    );
    expect(
      votingShareCompletionEstimateText(
        summaryAfter(const Duration(hours: 51, minutes: 42)),
        now: now,
      ),
      'Complete in about 2 days',
    );
    expect(
      votingShareCompletionEstimateText(
        summaryAfter(const Duration(minutes: -1)),
        now: now,
      ),
      'Completing soon',
    );
  });

  test('does not infer staggering from immediate-share creation times', () {
    final summary = VotingShareStatusSummary.fromRecords([
      _share(0, submitAt: BigInt.zero, createdAt: BigInt.from(100)),
      _share(1, submitAt: BigInt.zero, createdAt: BigInt.from(101)),
    ]);

    expect(summary.latestPendingDueAtSeconds, BigInt.from(101));
    expect(summary.usesStaggeredSubmission, isFalse);
  });

  test('closes share tracking when the round or deadline closes', () {
    final now = DateTime.utc(2026, 8, 23, 12);
    final voteEndTime = now.add(const Duration(hours: 1));

    expect(
      isVotingShareTrackingOpen(
        roundStatus: 'active',
        voteEndTime: voteEndTime,
        now: now,
      ),
      isTrue,
    );
    expect(
      isVotingShareTrackingOpen(
        roundStatus: 'complete',
        voteEndTime: voteEndTime,
        now: now,
      ),
      isFalse,
    );
    expect(
      isVotingShareTrackingOpen(
        roundStatus: 'active',
        voteEndTime: now,
        now: now,
      ),
      isFalse,
    );
  });

  testWidgets(
    'shows share progress, completion estimate, and handoff context',
    (tester) async {
      final now = DateTime.utc(2026, 8, 25, 12);
      final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
      await tester.pumpWidget(
        _harness(
          VotingShareStatusCard(
            records: [
              _share(0, confirmed: true),
              _share(1, submitAt: BigInt.from(nowSeconds + 20 * 60)),
              _share(
                2,
                submitAt: BigInt.from(nowSeconds + 2 * 60 * 60 + 20 * 60),
              ),
            ],
            now: now,
          ),
        ),
      );

      expect(find.text('Submission status'), findsOneWidget);
      expect(find.text('1 of 3 shares submitted'), findsOneWidget);
      expect(find.text('33%'), findsOneWidget);
      expect(find.text('Complete in about 2 hours'), findsOneWidget);
      expect(
        find.text(
          'To protect your privacy, Vizor splits your encrypted vote into '
          'shares that are submitted at different times, making them harder '
          'to link. You can close Vizor at any time while these servers submit '
          'your shares for you.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('seconds'), findsNothing);
      expect(find.textContaining('Scheduled'), findsNothing);
      expect(find.textContaining('Share 1'), findsNothing);
      expect(
        find.byKey(const ValueKey('voting_share_status_toggle')),
        findsNothing,
      );

      final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('voting_share_status_progress')),
      );
      expect(progress.value, closeTo(1 / 3, 0.0001));
    },
  );

  testWidgets('refreshes the completion estimate while the card stays open', (
    tester,
  ) async {
    final nowSeconds =
        DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    await tester.pumpWidget(
      _harness(
        VotingShareStatusCard(
          records: [_share(0, submitAt: BigInt.from(nowSeconds + 180))],
        ),
      ),
    );

    expect(find.text('Complete in about 3 minutes'), findsOneWidget);

    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Complete in about 2 minutes'), findsOneWidget);
    expect(find.text('Complete in about 3 minutes'), findsNothing);
  });

  testWidgets('describes an immediate single share without claiming a split', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 25, 12);
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    await tester.pumpWidget(
      _harness(
        VotingShareStatusCard(
          records: [
            _share(
              0,
              submitAt: BigInt.zero,
              createdAt: BigInt.from(nowSeconds),
            ),
          ],
          now: now,
        ),
      ),
    );

    expect(find.text('Completing soon'), findsOneWidget);
    expect(
      find.text(
        'Your encrypted vote is submitted as one encrypted share. You can '
        'close Vizor at any time while these servers submit your shares for '
        'you.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('submitted at different times'), findsNothing);
  });

  testWidgets('keeps incomplete share progress below 100 percent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        VotingShareStatusCard(
          records: [
            for (var index = 0; index < 200; index++)
              _share(index, confirmed: index < 199),
          ],
        ),
      ),
    );

    expect(find.text('199 of 200 shares submitted'), findsOneWidget);
    expect(find.text('99%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('voting_share_status_progress')),
    );
    expect(progress.value, closeTo(199 / 200, 0.0001));
  });

  testWidgets('shows a success icon after every share is submitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        VotingShareStatusCard(
          records: [_share(0, confirmed: true), _share(1, confirmed: true)],
        ),
      ),
    );

    expect(find.text('2 of 2 shares submitted'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voting_share_status_complete_icon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voting_share_status_percent')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('voting_share_status_progress')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('voting_share_status_completion_estimate')),
      findsNothing,
    );
    expect(find.textContaining('submitted at different times'), findsOneWidget);
    expect(find.textContaining('close Vizor'), findsNothing);
  });

  testWidgets('is informative but not interactive for assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(VotingShareStatusCard(records: [_share(0)])),
    );

    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('0 of 1 share submitted')),
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('does not render a card without persisted shares', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const VotingShareStatusCard(records: [])));

    expect(
      find.byKey(const ValueKey('voting_share_status_card')),
      findsNothing,
    );
  });
}

rust_wire.ShareDelegationRecordView _share(
  int shareIndex, {
  bool confirmed = false,
  BigInt? submitAt,
  BigInt? createdAt,
}) {
  return rust_wire.ShareDelegationRecordView(
    roundId: 'round-1',
    bundleIndex: 0,
    proposalId: 7,
    shareIndex: shareIndex,
    sentToUrls: const ['https://helper.example'],
    ambiguousUrls: const [],
    targetCount: 1,
    nullifier: Uint8List.fromList(List.filled(32, shareIndex)),
    phase: confirmed ? 'confirmed' : 'submitted_share',
    confirmed: confirmed,
    submitAt: submitAt ?? BigInt.from(1_777_000_000 + shareIndex),
    createdAt: createdAt ?? BigInt.from(1_777_000_000 + shareIndex),
  );
}

Widget _harness(Widget child) {
  return MaterialApp(
    builder: (context, appChild) =>
        AppTheme(data: AppThemeData.light, child: appChild!),
    home: Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: 420, child: child),
        ),
      ),
    ),
  );
}
