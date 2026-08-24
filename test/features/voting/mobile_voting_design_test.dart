@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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

  testWidgets('selected proposal matches the mobile card geometry', (
    tester,
  ) async {
    await _pumpMobileFixture(tester, buildMobileVotingProposalSelectedUseCase);

    final card = find.byType(VotingProposalCard);
    expect(card, findsOneWidget);
    expect(tester.getSize(card), const Size(361, 477));
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
    expect(tester.getSize(card), const Size(361, 375));
    expect(find.text('Option 2 (your vote)'), findsOneWidget);
    expect(find.text('490.36 ZEC'), findsWidgets);
  });

  testWidgets('long mobile metadata and option labels stay within the card', (
    tester,
  ) async {
    const title = 'A proposal with constrained mobile metadata';
    const optionLabel =
        'A very long option label that must remain on a single line';
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
              description: 'Description',
              zipNumber:
                  'ZIP-1000 ZIP-2000 ZIP-3000 ZIP-4000 ZIP-5000 ZIP-6000',
              options: [
                VotingOptionView(
                  index: 1,
                  label: optionLabel,
                  description:
                      'A description that occupies the supported two lines.',
                ),
              ],
            ),
            fallbackForumUri: Uri.parse('https://example.com/proposal'),
          ),
        ),
      ),
    );

    final metadata = find.textContaining('ZIP-1000');
    final option = tester.widget<Text>(find.text(optionLabel));
    expect(metadata, findsOneWidget);
    expect(
      tester.getBottomLeft(metadata).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text(title)).dy),
    );
    expect(option.maxLines, 1);
    expect(option.overflow, TextOverflow.ellipsis);
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

    await tester.tap(firstOption);
    await tester.pumpAndSettle();

    expect(tester.getRect(card), initialCardRect);
    expect(tester.getRect(firstOption), initialFirstOptionRect);
    expect(tester.getRect(secondOption), initialSecondOptionRect);
    expect(tester.getRect(label), initialLabelRect);
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
  WidgetBuilder builder,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: AppTheme(
        data: AppThemeData.dark,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
