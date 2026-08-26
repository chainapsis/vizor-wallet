@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_screens.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_proposal_detail_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_results_screen.dart';
import 'package:zcash_wallet/src/features/voting/voting_flow_models.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_pane_scroll_area.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFigmaCompareFonts);

  testWidgets('poll list matches Figma eligibility and active card geometry', (
    tester,
  ) async {
    await _pumpMobileFixture(tester, buildMobileVotingPollsEligibilityUseCase);
    final ineligible = find.byKey(
      const ValueKey('voting_poll_card_nu7-ineligible'),
    );
    final active = find.byKey(const ValueKey('voting_poll_card_nu7-active'));
    expect(tester.getTopLeft(ineligible), const Offset(16, 139));
    expect(tester.getSize(ineligible), const Size(361, 285.5));
    expect(tester.getTopLeft(active), const Offset(16, 448.5));
    expect(tester.getSize(active), const Size(361, 222.5));
    final label = tester.widget<Text>(find.text('Not eligible for this round'));
    expect(label.style?.color, AppThemeData.dark.colors.text.destructive);
    expect(label.style?.fontSize, 16);
    final action = find.byKey(
      const ValueKey('voting_poll_action_nu7-ineligible'),
    );
    expect(
      find.descendant(of: action, matching: find.text('View')),
      findsOneWidget,
    );
    expect(tester.widget<AppButton>(action).variant, AppButtonVariant.primary);
    expect(tester.widget<AppButton>(action).onPressed, isNotNull);
    final forum = find.byType(VotingForumLinkButton);
    expect(tester.getTopLeft(forum).dx, 32);
    expect(tester.getSize(forum).height, 24);
    expect(tester.widget<VotingForumLinkButton>(forum).mobilePollList, isTrue);
    await tester.drag(find.byType(VotingPaneListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Voted'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);
    expect(find.text('View results'), findsOneWidget);
    final votedDate = find.descendant(
      of: find.byKey(const ValueKey('voting_poll_card_snack-governance-voted')),
      matching: find.text('Closes Aug 24'),
    );
    expect(votedDate, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(votedDate).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('voting_poll_card_snack-governance-voted')),
      ),
      const Size(361, 248.5),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('voting_poll_card_snack-governance-closed')),
      ),
      const Size(361, 248.5),
    );
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('compact poll list remains usable at text scale $scale', (
      tester,
    ) async {
      await _pumpMobileFixture(
        tester,
        buildMobileVotingPollsEligibilityUseCase,
        size: const Size(320, 667),
        textScaler: TextScaler.linear(scale),
      );
      expect(find.text('Not eligible for this round'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      await tester.drag(
        find.byType(VotingPaneListView),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      expect(find.text('View results'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ineligible detail matches Figma and keeps the existing header', (
    tester,
  ) async {
    await _pumpMobileFixture(tester, buildMobileVotingIneligibleUseCase);

    final header = tester.widget<Text>(find.text('Coinholder voting'));
    expect(header.style?.fontFamily, 'Young Serif');
    expect(header.style?.fontSize, 32);
    final badge = find.byKey(const ValueKey('voting_detail_ineligible_badge'));
    expect(badge, findsOneWidget);
    expect(tester.getTopLeft(badge).dy, 140.5);
    expect(
      tester.getTopLeft(find.byType(VotingProposalCard)),
      const Offset(16, 371),
    );
    expect(find.textContaining('Voting power'), findsNothing);
    expect(find.textContaining('Ends Aug'), findsNothing);
    expect(tester.getTopLeft(find.text('Show description')).dx, 36);
    final option = find.byKey(const ValueKey('voting_proposal_1_option_1'));
    expect(tester.getTopLeft(option), const Offset(32, 678));
    expect(tester.getSize(option), const Size(329, 115));
    expect(
      tester
          .widget<Opacity>(
            find.descendant(of: option, matching: find.byType(Opacity)).first,
          )
          .opacity,
      1,
    );
    final label = find.descendant(of: option, matching: find.byType(Text));
    expect(tester.getSize(label).width, 305);
    expect(tester.widget<Text>(label).style?.fontWeight, FontWeight.w400);

    await tester.tap(find.text('Show description'));
    await tester.pumpAndSettle();
    expect(find.text('Hide description'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(VotingProposalCard)),
      const Offset(16, 371),
    );
    await tester.tap(find.text('Hide description'));
    await tester.pumpAndSettle();
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(find.text('Not eligible for this voting round'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voting_selected_choice_indicator')),
      findsNothing,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(VotingPaneScrollView),
      const Offset(0, -1000),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('voting_review_answers_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not eligible for this voting round'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'compact ineligible detail expands safely at text scale $scale',
      (tester) async {
        await _pumpMobileFixture(
          tester,
          buildMobileVotingIneligibleUseCase,
          size: const Size(320, 667),
          textScaler: TextScaler.linear(scale),
        );
        final card = find.byType(VotingProposalCard);
        final collapsedTop = tester.getTopLeft(card).dy;
        await tester.tap(find.text('Show description'));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(card).dy, greaterThan(collapsedTop));
        expect(find.byType(VotingForumLinkButton), findsOneWidget);
        await tester.drag(
          find.byType(VotingPaneScrollView),
          const Offset(0, -1600),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('voting_review_answers_button')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Not eligible for this voting round'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unknown eligibility keeps retry context without an ineligible badge',
    (tester) async {
      var retries = 0;
      await _pumpMobileFixture(
        tester,
        (_) => MobileVotingScaffold(
          title: 'Coinholder voting',
          child: VotingActivePollContent(
            showDesktopToolbar: false,
            roundId: 'retry',
            title: 'Retry round',
            snapshotHeight: 100,
            description: '',
            forumUri: Uri.parse('https://forum.zcashcommunity.com'),
            endDate: DateTime(2026, 8, 24),
            votingPowerZatoshi: null,
            votingPowerPreparing: false,
            votingEligibilityConfirmed: false,
            answersEditable: false,
            votingEligibilityMessage: 'Unable to check voting eligibility.',
            votingEligibilityErrorMessage: null,
            onVotingEligibilityRetry: () => retries++,
            proposals: const [
              VotingProposalView(
                id: 1,
                title: 'Question',
                description: '',
                options: [VotingOptionView(index: 1, label: 'Yes')],
              ),
            ],
            draft: const VotingDraftState(),
            onChoice: (_, _) =>
                fail('Unknown eligibility must not accept choices'),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('voting_detail_ineligible_badge')),
        findsNothing,
      );
      expect(find.text('Unable to check voting eligibility.'), findsOneWidget);
      expect(find.text('Ends Aug 24, 2026'), findsOneWidget);
      expect(find.byType(VotingForumLinkButton), findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.tap(find.text('Retry eligibility'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected proposal matches the mobile card geometry', (
    tester,
  ) async {
    await _pumpMobileFixture(tester, buildMobileVotingProposalSelectedUseCase);

    final card = find.byType(VotingProposalCard);
    expect(card, findsOneWidget);
    expect(tester.getSize(card), const Size(361, 562));
    expect(
      find.byKey(const ValueKey('voting_selected_choice_indicator')),
      findsOneWidget,
    );
  });

  testWidgets('voted state exposes the Figma review details', (tester) async {
    await _pumpMobileFixture(tester, buildMobileVotingVotedUseCase);

    expect(find.byType(VotingPaneScrollView), findsOneWidget);
    expect(find.byType(VotingPaneListView), findsNothing);
    expect(find.text('Voted'), findsWidgets);
    expect(find.text('Show description'), findsOneWidget);
    expect(find.text('Vote locked'), findsOneWidget);
    expect(find.text('0.375 ZEC'), findsOneWidget);
  });

  testWidgets('voted detail eagerly lays out its bounded proposal set', (
    tester,
  ) async {
    final proposals = List.generate(
      6,
      (index) => VotingProposalView(
        id: index,
        title: 'Proposal $index',
        description: 'Description for proposal $index',
        options: const [
          VotingOptionView(index: 0, label: 'Yes'),
          VotingOptionView(index: 1, label: 'No'),
        ],
      ),
    );
    await _pumpMobileFixture(
      tester,
      (_) => MobileVotingScaffold(
        title: 'Voted',
        child: VotingVotedPollContent(
          showDesktopToolbar: false,
          roundTitle: 'Bounded voting round',
          snapshotHeight: 1,
          description: 'Round description',
          forumUri: null,
          votingPowerZatoshi: BigInt.zero,
          votingPowerPreparing: false,
          votedAt: null,
          proposals: proposals,
          choicesByProposalId: const {},
        ),
      ),
    );

    expect(find.byType(VotingProposalCard), findsNWidgets(proposals.length));
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final initialMaxExtent = scrollable.position.maxScrollExtent;
    scrollable.position.jumpTo(initialMaxExtent / 2);
    await tester.pump();

    expect(scrollable.position.maxScrollExtent, initialMaxExtent);
  });

  testWidgets('results card matches the mobile geometry and selected vote', (
    tester,
  ) async {
    await _pumpMobileFixture(tester, buildMobileVotingResultsUseCase);

    final card = find.byType(VotingResultCard);
    expect(card, findsOneWidget);
    expect(tester.getSize(card), const Size(361, 378));
    expect(find.byType(VotingForumLinkButton), findsOneWidget);
    expect(find.text('Option 2 (your vote)'), findsOneWidget);
    expect(find.text('490.36 ZEC'), findsWidgets);
  });

  testWidgets('long mobile result labels remain fully visible', (tester) async {
    const optionLabel =
        'Ship NU7 as soon as possible, removing any feature that is not '
        'implemented by the September 30th deadline.';
    const displayedOptionLabel = '$optionLabel (your vote)';
    await _pumpMobileFixture(
      tester,
      (_) => const MobileVotingScaffold(
        title: 'Voting results',
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: VotingResultCard(
            proposal: VotingProposalView(
              id: 98,
              title: 'NU7 Scope and Readiness',
              description:
                  'How should features that are not ready by the deadline be '
                  'handled?',
              options: [VotingOptionView(index: 1, label: optionLabel)],
            ),
            tally: {1: 2.75},
            selectedChoice: 1,
          ),
        ),
      ),
    );

    final option = tester.widget<Text>(find.text(displayedOptionLabel));
    final row = find.ancestor(
      of: find.text(displayedOptionLabel),
      matching: find.byType(ClipRRect),
    );
    expect(option.maxLines, isNull);
    expect(option.overflow, isNull);
    expect(row, findsOneWidget);
    expect(tester.getSize(row).height, greaterThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long mobile question and option copy remains fully visible', (
    tester,
  ) async {
    const title =
        'A proposal title that wraps across multiple lines on a mobile screen';
    const proposalDescription =
        'A proposal description that must remain fully visible even when it '
        'takes several lines to explain the question to the voter.';
    const optionLabel =
        'Ship NU7 as soon as possible, removing any feature that is not '
        'implemented by the September 30th deadline.';
    const optionDescription =
        'This option description is intentionally long enough to exceed two '
        'lines so the complete explanation remains available before voting.';
    const optionKey = ValueKey('voting_proposal_99_option_1');
    await _pumpMobileFixture(
      tester,
      (_) => MobileVotingScaffold(
        title: 'Coinholder voting',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: VotingProposalCard(
            proposal: const VotingProposalView(
              id: 99,
              title: title,
              description: proposalDescription,
              zipNumber:
                  'ZIP-1000 ZIP-2000 ZIP-3000 ZIP-4000 ZIP-5000 ZIP-6000',
              options: [
                VotingOptionView(
                  index: 1,
                  label: optionLabel,
                  description: optionDescription,
                ),
              ],
            ),
            fallbackForumUri: Uri.parse('https://example.com/proposal'),
          ),
        ),
      ),
    );

    final metadata = find.textContaining('ZIP-1000');
    final proposalTitle = tester.widget<Text>(find.text(title));
    final description = tester.widget<Text>(find.text(proposalDescription));
    final option = tester.widget<Text>(find.text(optionLabel));
    final optionDescriptionText = tester.widget<Text>(
      find.text(optionDescription),
    );
    expect(metadata, findsOneWidget);
    expect(
      tester.getBottomLeft(metadata).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text(title)).dy),
    );
    expect(proposalTitle.maxLines, isNull);
    expect(proposalTitle.overflow, isNull);
    expect(description.maxLines, isNull);
    expect(description.overflow, isNull);
    expect(option.maxLines, isNull);
    expect(option.overflow, isNull);
    expect(optionDescriptionText.maxLines, isNull);
    expect(optionDescriptionText.overflow, isNull);
    expect(tester.getSize(find.byKey(optionKey)).height, greaterThan(94));
    expect(tester.getSize(find.byType(VotingForumLinkButton)).height, 24);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting a mobile option preserves option layout', (
    tester,
  ) async {
    const proposalId = 101;
    const firstOptionKey = ValueKey('voting_proposal_${proposalId}_option_0');
    const secondOptionKey = ValueKey('voting_proposal_${proposalId}_option_1');
    const longLabel =
        'A long voting option whose available width must remain stable';
    int? selectedChoice;

    await _pumpMobileFixture(
      tester,
      (_) => StatefulBuilder(
        builder: (context, setState) => MobileVotingScaffold(
          title: 'Coinholder voting',
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: VotingProposalCard(
              proposal: const VotingProposalView(
                id: proposalId,
                title: 'Stable option geometry',
                description: 'Selection must not move surrounding content.',
                options: [
                  VotingOptionView(index: 0, label: longLabel),
                  VotingOptionView(
                    index: 1,
                    label: 'Option with details',
                    description:
                        'This option verifies that a taller row also stays fixed.',
                  ),
                ],
              ),
              selectedChoice: selectedChoice,
              onChoice: (choice) => setState(() => selectedChoice = choice),
            ),
          ),
        ),
      ),
    );

    final card = find.byType(VotingProposalCard);
    final firstOption = find.byKey(firstOptionKey);
    final secondOption = find.byKey(secondOptionKey);
    final label = find.text(longLabel);
    final initialCardRect = tester.getRect(card);
    final initialFirstOptionRect = tester.getRect(firstOption);
    final initialSecondOptionRect = tester.getRect(secondOption);
    final initialLabelRect = tester.getRect(label);
    final firstOptionInkWell = tester.widget<InkWell>(
      find.descendant(of: firstOption, matching: find.byType(InkWell)),
    );
    expect(firstOptionInkWell.splashFactory, NoSplash.splashFactory);
    expect(
      firstOptionInkWell.overlayColor?.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    expect(
      firstOptionInkWell.overlayColor?.resolve({WidgetState.focused}),
      isNull,
    );
    expect(tester.widget<Text>(label).style?.fontWeight, FontWeight.w400);

    await tester.tap(firstOption);
    await tester.pumpAndSettle();

    expect(tester.getRect(card), initialCardRect);
    expect(tester.getRect(firstOption), initialFirstOptionRect);
    expect(tester.getRect(secondOption), initialSecondOptionRect);
    expect(tester.getRect(label), initialLabelRect);
    expect(tester.widget<Text>(label).style?.fontWeight, FontWeight.w400);
    expect(
      find.byKey(const ValueKey('voting_selected_choice_indicator')),
      findsOneWidget,
    );

    await tester.tap(secondOption);
    await tester.pumpAndSettle();

    expect(tester.getRect(card), initialCardRect);
    expect(tester.getRect(firstOption), initialFirstOptionRect);
    expect(tester.getRect(secondOption), initialSecondOptionRect);
    expect(tester.getRect(label), initialLabelRect);
    expect(
      find.byKey(const ValueKey('voting_selected_choice_indicator')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('voted mobile state retains the no-proposals explanation', (
    tester,
  ) async {
    await _pumpMobileFixture(
      tester,
      (_) => MobileVotingScaffold(
        title: 'Voted',
        child: VotingVotedPollContent(
          showDesktopToolbar: false,
          roundTitle: 'Empty voting round',
          snapshotHeight: 1,
          description: '',
          forumUri: null,
          votingPowerZatoshi: BigInt.zero,
          votingPowerPreparing: false,
          votedAt: null,
          proposals: const [],
          choicesByProposalId: const {},
        ),
      ),
    );

    expect(find.textContaining('No proposals'), findsOneWidget);
    expect(
      find.textContaining('This voting round does not contain any proposals.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpMobileFixture(
  WidgetTester tester,
  WidgetBuilder builder, {
  Size size = const Size(393, 852),
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => AppTheme(
        data: AppThemeData.dark,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
      ),
      home: Builder(builder: builder),
    ),
  );
  await tester.pumpAndSettle();
}
