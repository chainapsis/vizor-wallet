import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_auto_advance_indicator.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/widgetbook/voting_navigation_preview.dart';

final proposals = [
  for (final id in [7, 21, 45, 91])
    VotingProposalView(
      id: id,
      title: 'Proposal $id',
      description: List.filled(
        12,
        'Read this proposal before choosing.',
      ).join(' '),
      options: const [
        VotingOptionView(index: 0, label: 'Accept'),
        VotingOptionView(index: 1, label: 'Reject'),
        VotingOptionView(index: 2, label: 'Reconsider'),
        VotingOptionView(index: 3, label: 'Abstain'),
      ],
    ),
];

Future<void> pumpBallot(WidgetTester tester, Map<int, int> choices) async {
  tester.view.physicalSize = const Size(393, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
      home: Scaffold(
        body: VotingNavigationPreview(
          proposals: proposals,
          initialChoices: choices,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollController ballotScroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
    .controller!;

Future<void> choose(WidgetTester tester, int id, int choice) async {
  final option = find.byKey(ValueKey('voting_proposal_${id}_option_$choice'));
  await Scrollable.ensureVisible(tester.element(option), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(option);
  await tester.pump();
}

Future<void> finishAdvance(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first answer waits then advances to the next unanswered ID', (
    tester,
  ) async {
    await pumpBallot(tester, {1: 0, 2: 0});
    await choose(tester, 7, 0);
    expect(find.byType(VotingAutoAdvanceIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    final progress = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(VotingAutoAdvanceIndicator),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(progress.value, closeTo(.5, .05));
    final before = ballotScroll(tester).offset;
    await tester.pump(const Duration(milliseconds: 299));
    expect(ballotScroll(tester).offset, before);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
    expect(find.byKey(const ValueKey('jump-highlight-91')), findsOneWidget);
    expect(ballotScroll(tester).offset, greaterThan(before));
    expect(find.textContaining('Next unanswered'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final choice in [1, null]) {
    testWidgets(
      'editing or clearing during the pause cancels advance: $choice',
      (tester) async {
        await pumpBallot(tester, {});
        await choose(tester, 7, 0);
        await tester.pump(const Duration(milliseconds: 100));
        tester
            .widget<VotingProposalCard>(find.byType(VotingProposalCard).first)
            .onChoice!(choice);
        await tester.pump();
        final before = ballotScroll(tester).offset;
        await finishAdvance(tester);
        expect(ballotScroll(tester).offset, before);
        expect(find.byKey(const ValueKey('jump-highlight-21')), findsNothing);
      },
    );
  }

  for (final completeFirstAdvance in [false, true]) {
    testWidgets(
      'clearing and reselecting never repeats an advance: $completeFirstAdvance',
      (tester) async {
        await pumpBallot(tester, {});
        await choose(tester, 7, 0);
        expect(find.byType(VotingAutoAdvanceIndicator), findsOneWidget);
        if (completeFirstAdvance) {
          await finishAdvance(tester);
          await choose(tester, 7, 0);
        } else {
          // Clear before the countdown finishes, canceling its first advance.
          tester
              .widget<VotingProposalCard>(find.byType(VotingProposalCard).first)
              .onChoice!(null);
          await tester.pump();
        }
        await choose(tester, 7, 1);
        expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
        final before = ballotScroll(tester).offset;
        await finishAdvance(tester);
        expect(ballotScroll(tester).offset, before);
      },
    );
  }

  testWidgets('clearing a restored answer does not make it a first answer', (
    tester,
  ) async {
    await pumpBallot(tester, {0: 0});
    await choose(tester, 7, 0);
    await choose(tester, 7, 1);
    expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
    final before = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, before);
  });

  testWidgets('manual drag cancels a pending advance', (tester) async {
    await pumpBallot(tester, {});
    await choose(tester, 7, 0);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -70),
    );
    await tester.pumpAndSettle();
    final before = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, before);
    expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
    expect(find.byKey(const ValueKey('jump-highlight-21')), findsNothing);
  });

  testWidgets(
    'touch interrupts an advance already in motion without moving focus',
    (tester) async {
      await pumpBallot(tester, {});
      await choose(tester, 7, 0);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 80));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SingleChildScrollView).first),
      );
      final before = ballotScroll(tester).offset;
      await tester.pump(const Duration(milliseconds: 500));
      expect(ballotScroll(tester).offset, before);
      expect(find.byKey(const ValueKey('jump-highlight-21')), findsNothing);
      await gesture.up();
    },
  );

  testWidgets('mouse wheel and keyboard navigation cancel the pause', (
    tester,
  ) async {
    await pumpBallot(tester, {});
    await choose(tester, 7, 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(SingleChildScrollView).first),
        scrollDelta: const Offset(0, 50),
      ),
    );
    await tester.pumpAndSettle();
    final afterWheel = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, afterWheel);
    await choose(tester, 21, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final afterTab = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, afterTab);
    expect(find.byKey(const ValueKey('jump-highlight-45')), findsNothing);
  });

  testWidgets('opening another route prevents a delayed move underneath it', (
    tester,
  ) async {
    await pumpBallot(tester, {});
    await choose(tester, 7, 0);
    final scroll = ballotScroll(tester);
    final before = scroll.offset;
    final context = tester.element(find.byType(VotingNavigationPreview));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('Dialog')),
    );
    await tester.pump();
    await finishAdvance(tester);
    expect(scroll.offset, before);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(scroll.offset, before);
  });

  testWidgets('only earlier unanswered means stay on the current question', (
    tester,
  ) async {
    await pumpBallot(tester, {1: 0, 2: 0});
    await choose(tester, 91, 0);
    expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
    final before = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, before);
    expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
    expect(find.byKey(const ValueKey('jump-highlight-7')), findsNothing);
    expect(find.text('3 / 4 answered'), findsOneWidget);
  });

  testWidgets('restored answers and edits do not advance', (tester) async {
    await pumpBallot(tester, {0: 0});
    final before = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, before);
    await choose(tester, 7, 1);
    final edited = ballotScroll(tester).offset;
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, edited);
  });

  testWidgets('completion stays in place and does not open review', (
    tester,
  ) async {
    await pumpBallot(tester, {1: 0, 2: 0, 3: 0});
    await choose(tester, 7, 0);
    expect(find.byType(VotingAutoAdvanceIndicator), findsNothing);
    final before = ballotScroll(tester).offset;
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(ballotScroll(tester).offset, before);
    expect(find.text('Review your answers'), findsNothing);
    expect(find.byKey(const ValueKey('sticky-review-action')), findsOneWidget);
  });

  testWidgets('backgrounding and disposal cancel the pending timer', (
    tester,
  ) async {
    await pumpBallot(tester, {});
    await choose(tester, 7, 0);
    final before = ballotScroll(tester).offset;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await finishAdvance(tester);
    expect(ballotScroll(tester).offset, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
