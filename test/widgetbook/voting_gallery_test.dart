import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/screens/mobile/mobile_voting_submission_progress_screen.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_status_screen.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_metadata_widgets.dart';
import 'package:zcash_wallet/src/features/voting/widgets/voting_pane_scroll_area.dart';
import 'package:zcash_wallet/widgetbook/gallery/voting_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';
import 'package:zcash_wallet/widgetbook/voting_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';
import 'package:zcash_wallet/widgetbook/widgetbook_app.dart';

import 'support/wb_gallery_harness.dart';

// Lane-agnostic, and both lanes are expected to pass. The desktop shell the
// screen fixtures sit in (`AppMainSidebar`) overflows by 2px under mobile
// tokens, and several copy assertions belong to one form factor's widget
// class, so every desktop-pinned render is gated on [_desktopLane] and the
// lane-specific expectations branch on it.
const _desktopLane = wbCompiledLaneLayout == WbLayout.desktop;
final _lane = wbLayoutLabel(wbCompiledLaneLayout);

void main() {
  /// The provider-driven screens settle their session, rounds and tally reads
  /// one or two frames after mount, so these cases are fingerprinted by hand
  /// instead of through `expectKnobOptionsRenderDistinctly`.
  Future<String> pumpSettled(
    WidgetTester tester,
    WidgetBuilder builder,
    Map<String, String> knobs,
  ) async {
    await pumpUseCase(tester, builder, knobs: knobs);
    // The poll list settles through config refresh, rounds reload and then a
    // per-card eligibility future, so one extra frame is not enough.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump();
    }
    expect(tester.takeException(), isNull, reason: '$knobs');
    return useCaseFingerprint(tester);
  }

  Future<void> expectSettledOptionsDistinct(
    WidgetTester tester,
    WidgetBuilder builder, {
    required String label,
    required List<String> optionLabels,
    Map<String, String> otherKnobs = const {},
  }) async {
    final seen = <String, String>{};
    for (final option in optionLabels) {
      final fingerprint = await pumpSettled(tester, builder, {
        ...otherKnobs,
        label: option,
      });
      expect(
        seen[fingerprint],
        isNull,
        reason:
            "'$label' options '${seen[fingerprint]}' and '$option' render "
            'identically.',
      );
      seen[fingerprint] = option;
    }
    await disposeTree(tester);
  }

  testWidgets('every voting gallery case builds at its knob defaults', (
    tester,
  ) async {
    final useCases = widgetbookUseCases(votingGalleryNodes).toList();
    expect(useCases.length, 22);

    for (final useCase in useCases) {
      await pumpUseCase(tester, useCase.builder);
      expect(tester.takeException(), isNull, reason: useCase.name);
    }
    await disposeTree(tester);
  });

  testWidgets('poll list covers both layouts and every list state', (
    tester,
  ) async {
    await expectSettledOptionsDistinct(
      tester,
      buildVotingPollListCase,
      label: 'Rounds',
      optionLabels: VotingPollRoundsCase.values
          .map(votingPollRoundsLabel)
          .toList(),
      // Mobile: only the mobile card reads eligibility and participation, so
      // the two eligibility lists are one render on desktop.
      otherKnobs: const {'Layout': 'Mobile'},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingPollListCase,
      label: 'Load',
      optionLabels: VotingPollLoadCase.values.map(votingPollLoadLabel).toList(),
      otherKnobs: {'Layout': _lane},
    );
    if (_desktopLane) {
      await expectSettledOptionsDistinct(
        tester,
        buildVotingPollListCase,
        label: 'Layout',
        optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      );
    }

    Future<void> pumpList({
      VotingPollRoundsCase rounds = VotingPollRoundsCase.rounds,
      VotingPollLoadCase load = VotingPollLoadCase.loaded,
    }) async {
      await pumpSettled(tester, buildVotingPollListCase, {
        'Layout': _lane,
        'Rounds': votingPollRoundsLabel(rounds),
        'Load': votingPollLoadLabel(load),
      });
    }

    await pumpList();
    expect(find.text('NU7 Scope'), findsOneWidget);
    await pumpList(load: VotingPollLoadCase.loading);
    expect(find.byType(VotingPaneLoading), findsOneWidget);
    await pumpList(load: VotingPollLoadCase.failed);
    expect(find.text("Couldn't load voting rounds"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await pumpList(rounds: VotingPollRoundsCase.empty);
    expect(find.text('No voting rounds available'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('poll card covers status, date, forum and eligibility', (
    tester,
  ) async {
    await expectSettledOptionsDistinct(
      tester,
      buildVotingPollCardCase,
      label: 'Status',
      optionLabels: VotingPollCardState.values
          .map(votingPollCardStateLabel)
          .toList(),
      otherKnobs: {'Layout': _lane},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingPollCardCase,
      label: 'Date',
      optionLabels: VotingPollCardDate.values
          .map(votingPollCardDateLabel)
          .toList(),
      otherKnobs: {'Layout': _lane},
    );
    // Only the mobile card reads eligibility, and only while the round is
    // active.
    await expectSettledOptionsDistinct(
      tester,
      buildVotingPollCardCase,
      label: 'Eligibility',
      optionLabels: votingPollCardEligibilityOptions
          .map(votingPollCardEligibilityLabel)
          .toList(),
      otherKnobs: {
        'Layout': 'Mobile',
        'Status': votingPollCardStateLabel(VotingPollCardState.active),
      },
    );

    Future<void> pumpCard(Map<String, String> knobs) async {
      await pumpSettled(tester, buildVotingPollCardCase, {
        'Layout': _lane,
        ...knobs,
      });
    }

    await pumpCard({
      'Status': votingPollCardStateLabel(VotingPollCardState.inProgress),
    });
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await pumpCard({
      'Status': votingPollCardStateLabel(VotingPollCardState.voted),
    });
    expect(find.text('Review'), findsOneWidget);
    await pumpCard({
      'Status': votingPollCardStateLabel(VotingPollCardState.tallying),
    });
    expect(find.text('Tallying'), findsOneWidget);
    expect(find.text('View results'), findsOneWidget);
    await pumpCard({
      'Date': votingPollCardDateLabel(VotingPollCardDate.startDate),
    });
    expect(find.textContaining('Starts '), findsOneWidget);
    await pumpCard({'Date': votingPollCardDateLabel(VotingPollCardDate.none)});
    expect(find.textContaining('Closes '), findsNothing);
    await pumpCard(const {'Empty title and description': 'true'});
    // Both the title and the description fall back to the round id.
    expect(find.text('nu7-scope-active'), findsNWidgets(2));
    await pumpCard(const {'Forum link': 'false'});
    expect(find.text('Forum'), findsNothing);

    // An unfinished or failed check must not read as ineligible, which is why
    // neither is a knob option.
    for (final eligibility in const [
      VotingPollCardEligibility.checking,
      VotingPollCardEligibility.checkFailed,
    ]) {
      await pumpSettled(
        tester,
        (context) => votingPollCardFixture(
          layout: WbLayout.mobile,
          eligibility: eligibility,
        ),
        const {},
      );
      expect(
        find.text('Not eligible for this round'),
        findsNothing,
        reason: '$eligibility',
      );
    }
    await disposeTree(tester);
  });

  testWidgets('poll card routes its forum link through the preview launcher', (
    tester,
  ) async {
    final launched = <Uri>[];
    await pumpSettled(
      tester,
      (context) => votingPollCardFixture(
        layout: wbCompiledLaneLayout,
        launchExternalUri: (uri) async => launched.add(uri),
      ),
      const {},
    );

    await tester.tap(find.byType(VotingForumLinkButton));
    await tester.pump();

    expect(launched, [
      Uri.parse('https://forum.zcashcommunity.com/t/nu7-scope'),
    ]);
    await disposeTree(tester);
  });

  testWidgets('proposal detail covers session, content and voting power', (
    tester,
  ) async {
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    await expectSettledOptionsDistinct(
      tester,
      buildVotingProposalDetailCase,
      label: 'Session',
      optionLabels: VotingDetailSessionCase.values
          .map(votingDetailSessionLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingProposalDetailCase,
      label: 'Content',
      optionLabels: VotingDetailBranchCase.values
          .map(votingDetailBranchLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingProposalDetailCase,
      label: 'Voting power',
      optionLabels: VotingDetailPowerCase.values
          .map(votingDetailPowerLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );

    Future<void> pumpDetail(Map<String, String> knobs) async {
      await pumpSettled(tester, buildVotingProposalDetailCase, {
        'Layout': lane,
        ...knobs,
      });
    }

    await pumpDetail({
      'Session': votingDetailSessionLabel(VotingDetailSessionCase.failed),
    });
    expect(find.textContaining("Couldn't load voting round"), findsOneWidget);
    await pumpDetail({
      'Session': votingDetailSessionLabel(
        VotingDetailSessionCase.roundUnavailable,
      ),
    });
    expect(find.textContaining('Voting round unavailable'), findsOneWidget);
    await pumpDetail({
      'Content': votingDetailBranchLabel(VotingDetailBranchCase.voteInProgress),
    });
    expect(find.text('Vote in progress'), findsOneWidget);
    expect(find.text('Continue voting'), findsOneWidget);
    await pumpDetail({
      'Content': votingDetailBranchLabel(
        VotingDetailBranchCase.redirectToResults,
      ),
    });
    expect(
      find.text('Preview navigated to /voting/poll/:roundId/results'),
      findsOneWidget,
    );
    await pumpDetail({
      'Voting power': votingDetailPowerLabel(VotingDetailPowerCase.preparing),
    });
    expect(find.text('Preparing voting power'), findsOneWidget);
    await pumpDetail({
      'Voting power': votingDetailPowerLabel(VotingDetailPowerCase.unavailable),
    });
    expect(find.text('Voting power unavailable'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('proposal detail previews the other layout only in its lane', (
    tester,
  ) async {
    final other = wbCompiledLaneLayout == WbLayout.desktop
        ? WbLayout.mobile
        : WbLayout.desktop;
    await pumpUseCase(
      tester,
      buildVotingProposalDetailCase,
      knobs: {'Layout': wbLayoutLabel(other)},
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('results cover the tally, the account vote and empty rounds', (
    tester,
  ) async {
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    await expectSettledOptionsDistinct(
      tester,
      buildVotingResultsCase,
      label: 'Tally',
      optionLabels: VotingResultsTallyCase.values
          .map(votingResultsTallyLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingResultsCase,
      label: 'Your vote',
      optionLabels: VotingResultsVotedCase.values
          .map(votingResultsVotedLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingResultsCase,
      label: 'Proposals',
      optionLabels: VotingResultsProposalsCase.values
          .map(votingResultsProposalsLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );

    Future<void> pumpResults(Map<String, String> knobs) async {
      await pumpSettled(tester, buildVotingResultsCase, {
        'Layout': lane,
        ...knobs,
      });
    }

    await pumpResults(const {});
    // The tally footer is the desktop card's; the mobile card labels the
    // winning row instead.
    expect(
      _desktopLane ? find.textContaining('Total: ') : find.text('Winner'),
      findsWidgets,
    );
    await pumpResults({
      'Tally': votingResultsTallyLabel(VotingResultsTallyCase.pending),
    });
    expect(find.text('Results pending...'), findsOneWidget);
    await pumpResults({
      'Tally': votingResultsTallyLabel(VotingResultsTallyCase.failed),
    });
    expect(find.textContaining("Couldn't load results"), findsOneWidget);
    await pumpResults({
      'Tally': votingResultsTallyLabel(VotingResultsTallyCase.loading),
    });
    expect(find.byType(VotingPaneLoading), findsOneWidget);
    await pumpResults({
      'Proposals': votingResultsProposalsLabel(VotingResultsProposalsCase.none),
    });
    expect(find.text('No proposals in this round.'), findsOneWidget);
    await disposeTree(tester);
  });

  /// A boolean knob renders two different things; the option labels a boolean
  /// field encodes are the strings 'true' and 'false'.
  Future<void> expectBoolKnobDistinct(
    WidgetTester tester,
    WidgetBuilder builder, {
    required String label,
    Map<String, String> otherKnobs = const {},
  }) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      builder,
      label: label,
      optionLabels: const ['true', 'false'],
      otherKnobs: otherKnobs,
    );
  }

  testWidgets('voting config settings covers sources, load state and rounds', (
    tester,
  ) async {
    const desktop = 'Desktop';
    await expectSettledOptionsDistinct(
      tester,
      buildVotingSettingsSheetCase,
      label: 'Sources',
      optionLabels: VotingConfigSourcesCase.values
          .map(votingConfigSourcesLabel)
          .toList(),
      otherKnobs: {'Layout': desktop},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingSettingsSheetCase,
      label: 'Config',
      optionLabels: VotingConfigLoadCase.values
          .map(votingConfigLoadLabel)
          .toList(),
      otherKnobs: {'Layout': desktop},
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingSettingsSheetCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );
    await expectSettledOptionsDistinct(
      tester,
      buildVotingSettingsSheetCase,
      label: 'Test rounds',
      optionLabels: const ['true', 'false'],
      otherKnobs: {'Layout': desktop},
    );
    for (final layout in WbLayout.values) {
      await expectSettledOptionsDistinct(
        tester,
        buildVotingSettingsSheetCase,
        label: 'Editor',
        optionLabels: VotingConfigEditorCase.values
            .map(votingConfigEditorLabel)
            .toList(),
        otherKnobs: {'Layout': wbLayoutLabel(layout)},
      );
    }

    Future<void> pumpSettings(Map<String, String> knobs) async {
      await pumpSettled(tester, buildVotingSettingsSheetCase, {
        'Layout': desktop,
        ...knobs,
      });
    }

    await pumpSettings(const {});
    expect(find.text('Voting config'), findsOneWidget);
    expect(find.text('Token holder voting'), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Add custom source'), findsOneWidget);
    await pumpSettings({
      'Sources': votingConfigSourcesLabel(VotingConfigSourcesCase.defaultOnly),
    });
    expect(find.text('Community'), findsNothing);
    expect(find.text('Default'), findsOneWidget);
    await pumpSettings({
      'Sources': votingConfigSourcesLabel(
        VotingConfigSourcesCase.customSelected,
      ),
    });
    expect(find.text('Active'), findsOneWidget);
    await pumpSettings({
      'Config': votingConfigLoadLabel(VotingConfigLoadCase.loading),
    });
    expect(find.text('Show test rounds'), findsNothing);
    await pumpSettings({
      'Config': votingConfigLoadLabel(VotingConfigLoadCase.failed),
    });
    expect(
      find.textContaining("Couldn't load the saved voting config sources."),
      findsOneWidget,
    );
    // The add control opens each surface's own editor form, whose title
    // repeats the control's words — the URL field is what only the form has.
    await pumpSettings(const {});
    expect(find.text('Static config URL'), findsNothing);
    await pumpSettings({
      'Editor': votingConfigEditorLabel(VotingConfigEditorCase.addingSource),
    });
    expect(find.text('Static config URL'), findsOneWidget);
    await pumpSettings({
      'Editor': votingConfigEditorLabel(VotingConfigEditorCase.editingSource),
    });
    expect(find.text('Edit custom source'), findsOneWidget);
    // The edit control only exists on a saved source, so the editing option
    // pins one even when the Sources knob asks for the default list.
    await pumpSettings({
      'Sources': votingConfigSourcesLabel(VotingConfigSourcesCase.defaultOnly),
      'Editor': votingConfigEditorLabel(VotingConfigEditorCase.editingSource),
    });
    expect(find.text('Edit custom source'), findsOneWidget);
    await pumpSettled(tester, buildVotingSettingsSheetCase, {
      'Layout': wbLayoutLabel(WbLayout.mobile),
      'Editor': votingConfigEditorLabel(VotingConfigEditorCase.addingSource),
    });
    expect(find.text('Source URL'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('voting config editor reopens when the option changes in place', (
    tester,
  ) async {
    // The live widgetbook rebuilds the use case without remounting, unlike
    // `pumpUseCase`; the driver has to re-run for the second option.
    final editor = ValueNotifier(VotingConfigEditorCase.addingSource);
    addTearDown(editor.dispose);
    Future<void> settle() async {
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: '${editor.value}');
    }

    await pumpUseCase(
      tester,
      (context) => ValueListenableBuilder(
        valueListenable: editor,
        builder: (context, value, _) => votingConfigSettingsFixture(
          layout: WbLayout.desktop,
          editor: value,
        ),
      ),
    );
    await settle();
    expect(find.text('Static config URL'), findsOneWidget);
    expect(find.text('Edit custom source'), findsNothing);
    editor.value = VotingConfigEditorCase.editingSource;
    await settle();
    expect(find.text('Edit custom source'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('ineligible dialog covers the guidance line in its own lane', (
    tester,
  ) async {
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    await expectBoolKnobDistinct(
      tester,
      buildVotingIneligibleDialogCase,
      label: 'Guidance line',
      otherKnobs: {'Layout': lane},
    );

    await pumpUseCase(
      tester,
      buildVotingIneligibleDialogCase,
      knobs: {'Layout': lane},
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Not eligible'), findsOneWidget);
    expect(
      find.textContaining('Switch to an eligible account to vote.'),
      findsOneWidget,
    );
    await pumpUseCase(
      tester,
      buildVotingIneligibleDialogCase,
      knobs: {'Layout': lane, 'Guidance line': 'false'},
    );
    expect(
      find.textContaining('Switch to an eligible account to vote.'),
      findsNothing,
    );

    final other = wbCompiledLaneLayout == WbLayout.desktop
        ? WbLayout.mobile
        : WbLayout.desktop;
    await pumpUseCase(
      tester,
      buildVotingIneligibleDialogCase,
      knobs: {'Layout': wbLayoutLabel(other)},
    );
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('skipped questions dialog covers every unanswered count', (
    tester,
  ) async {
    // The dialog's 312px buttons overflow under mobile tokens, so the case
    // pins the desktop lane and shows the run-command notice in the other.
    if (!_desktopLane) {
      await pumpUseCase(tester, buildVotingSkippedQuestionsDialogCase);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
      await disposeTree(tester);
      return;
    }

    // The counts differ only in digits, which the test font paints as
    // identical boxes, so this knob is swept by its copy, not a fingerprint.
    const counts = {
      VotingSkippedQuestionsCase.one: '1 of 12',
      VotingSkippedQuestionsCase.some: '4 of 12',
      VotingSkippedQuestionsCase.all: '12 of 12',
    };
    for (final entry in counts.entries) {
      await pumpUseCase(
        tester,
        buildVotingSkippedQuestionsDialogCase,
        knobs: {'Unanswered': votingSkippedQuestionsLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: entry.key.name);
      expect(find.text('Skip unanswered questions?'), findsOneWidget);
      expect(
        find.textContaining('You have not answered ${entry.value} questions'),
        findsOneWidget,
        reason: entry.key.name,
      );
    }

    await pumpUseCase(tester, buildVotingSkippedQuestionsDialogCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Continue to review'), findsOneWidget);
    expect(find.text('Keep voting'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('skip signed bundles dialog renders in both frames', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingSkipSignedBundlesDialogCase,
      label: 'Layout',
      optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
    );

    await pumpUseCase(
      tester,
      buildVotingSkipSignedBundlesDialogCase,
      knobs: {'Layout': _lane},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Use signed bundles only?'), findsOneWidget);
    expect(find.text('Skip bundles'), findsOneWidget);
    expect(find.text('Keep signing'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('result card covers the tally, the vote marker and metadata', (
    tester,
  ) async {
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingResultCardCase,
      label: 'Winner',
      optionLabels: VotingResultWinnerCase.values
          .map(votingResultWinnerLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingResultCardCase,
      label: 'Your vote',
      optionLabels: VotingResultVoteCase.values
          .map(votingResultVoteLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingResultCardCase,
      label: 'Share',
      optionLabels: VotingResultShareCase.values
          .map(votingResultShareLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectBoolKnobDistinct(
      tester,
      buildVotingResultCardCase,
      label: 'Metadata',
      otherKnobs: {'Layout': lane},
    );
    if (wbCompiledLaneLayout == WbLayout.mobile) {
      // Only the mobile row carries the voter's avatar.
      await expectBoolKnobDistinct(
        tester,
        buildVotingResultCardCase,
        label: 'Avatar',
        otherKnobs: {
          'Layout': lane,
          'Your vote': votingResultVoteLabel(VotingResultVoteCase.winning),
        },
      );
    }

    Future<void> pumpResultCard(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingResultCardCase,
        knobs: {'Layout': lane, ...knobs},
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    await pumpResultCard(const {});
    expect(find.text('Yes, adopt the proposal'), findsOneWidget);
    expect(find.text('Forum discussion'), findsOneWidget);
    await pumpResultCard(const {'Metadata': 'false'});
    expect(find.text('Forum discussion'), findsNothing);
    if (wbCompiledLaneLayout == WbLayout.mobile) {
      await pumpResultCard(const {});
      expect(find.text('Winner'), findsOneWidget);
      expect(find.text('Your vote'), findsOneWidget);
      await pumpResultCard({
        'Winner': votingResultWinnerLabel(VotingResultWinnerCase.tie),
      });
      expect(find.text('Winner'), findsNothing);
      await pumpResultCard({
        'Share': votingResultShareLabel(VotingResultShareCase.tiny),
      });
      expect(find.textContaining('<0.1%'), findsOneWidget);
      await pumpResultCard({
        'Share': votingResultShareLabel(VotingResultShareCase.zero),
      });
      expect(find.textContaining('(0%)'), findsOneWidget);
    } else {
      await pumpResultCard(const {});
      expect(find.textContaining('Total: '), findsOneWidget);
      expect(find.textContaining('Voted: '), findsOneWidget);
      await pumpResultCard({
        'Winner': votingResultWinnerLabel(VotingResultWinnerCase.none),
      });
      expect(find.textContaining('Total: '), findsNothing);
      await pumpResultCard({
        'Your vote': votingResultVoteLabel(VotingResultVoteCase.none),
      });
      expect(find.textContaining('Voted: '), findsNothing);
    }
    await disposeTree(tester);
  });

  testWidgets('proposal card covers mode, selection, tone and metadata', (
    tester,
  ) async {
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    final missing = votingProposalCardChoiceLabel(
      VotingProposalCardChoiceCase.missingOption,
    );
    final firstOption = votingProposalCardChoiceLabel(
      VotingProposalCardChoiceCase.firstOption,
    );
    const indicator = ValueKey('voting_selected_choice_indicator');

    Future<void> pumpProposalCard(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingProposalCardCase,
        knobs: {'Layout': lane, ...knobs},
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    if (wbCompiledLaneLayout == WbLayout.desktop) {
      // Read-only is what synthesizes the missing-option row; the other two
      // modes differ in the desktop row's trailing label and colours.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingProposalCardCase,
        label: 'Mode',
        optionLabels: VotingProposalCardModeCase.values
            .map(votingProposalCardModeLabel)
            .toList(),
        otherKnobs: {'Layout': lane, 'Selection': missing},
      );
    } else {
      // The mobile option row has no trailing label, so each mode gets the
      // one thing that is only true of it.
      await pumpProposalCard({
        'Mode': votingProposalCardModeLabel(
          VotingProposalCardModeCase.interactive,
        ),
        'Selection': firstOption,
      });
      expect(find.byKey(indicator), findsOneWidget);
      await pumpProposalCard({
        'Mode': votingProposalCardModeLabel(
          VotingProposalCardModeCase.readOnly,
        ),
        'Selection': missing,
      });
      expect(find.text('Choice 7'), findsOneWidget);
      await pumpProposalCard({
        'Mode': votingProposalCardModeLabel(
          VotingProposalCardModeCase.disabled,
        ),
        'Selection': firstOption,
      });
      expect(find.byKey(indicator), findsNothing);
    }
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingProposalCardCase,
      label: 'Selection',
      optionLabels: VotingProposalCardChoiceCase.values
          .map(votingProposalCardChoiceLabel)
          .toList(),
      otherKnobs: {
        'Layout': lane,
        'Mode': votingProposalCardModeLabel(
          VotingProposalCardModeCase.readOnly,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingProposalCardCase,
      label: 'Tone',
      optionLabels: VotingProposalCardToneCase.values
          .map(votingProposalCardToneLabel)
          .toList(),
      otherKnobs: {
        'Layout': lane,
        'Selection': votingProposalCardChoiceLabel(
          VotingProposalCardChoiceCase.firstOption,
        ),
      },
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingProposalCardCase,
      label: 'Metadata',
      optionLabels: VotingProposalCardMetadataCase.values
          .map(votingProposalCardMetadataLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectBoolKnobDistinct(
      tester,
      buildVotingProposalCardCase,
      label: 'Skipped status',
      otherKnobs: {'Layout': lane},
    );
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      // Only the desktop card reads `titleCollapsedMaxLines`.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingProposalCardCase,
        label: 'Title',
        optionLabels: VotingProposalCardTitleCase.values
            .map(votingProposalCardTitleLabel)
            .toList(),
        otherKnobs: {'Layout': lane},
      );
    }

    await pumpProposalCard({
      'Mode': votingProposalCardModeLabel(VotingProposalCardModeCase.readOnly),
      'Selection': missing,
    });
    expect(find.text('Choice 7'), findsOneWidget);
    await pumpProposalCard(const {'Skipped status': 'true'});
    expect(find.textContaining('Skipped'), findsOneWidget);
    await pumpProposalCard({
      'Metadata': votingProposalCardMetadataLabel(
        VotingProposalCardMetadataCase.none,
      ),
    });
    expect(find.textContaining('ZIP-233'), findsNothing);
    expect(find.text('Forum discussion'), findsNothing);
    await pumpProposalCard({
      'Metadata': votingProposalCardMetadataLabel(
        VotingProposalCardMetadataCase.oneBadge,
      ),
    });
    expect(find.textContaining('ZIP-233'), findsWidgets);
    expect(find.text('Forum discussion'), findsNothing);
    await pumpProposalCard(const {});
    expect(find.text('Forum discussion'), findsOneWidget);
    await pumpProposalCard({
      'Tone': votingProposalCardToneLabel(VotingProposalCardToneCase.yes),
    });
    expect(find.text('Yes, adopt the proposal'), findsOneWidget);
    if (wbCompiledLaneLayout == WbLayout.desktop) {
      await pumpProposalCard({
        'Title': votingProposalCardTitleLabel(
          VotingProposalCardTitleCase.collapsible,
        ),
      });
      expect(find.text('View more'), findsOneWidget);
    }
    await disposeTree(tester);
  });

  testWidgets('expandable text covers length, controls and the fixed toggle', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingExpandableTextCase,
      label: 'Text',
      optionLabels: VotingExpandableTextCase.values
          .map(votingExpandableTextLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingExpandableTextCase,
      label: 'Controls',
      optionLabels: VotingExpandableControlsCase.values
          .map(votingExpandableControlsLabel)
          .toList(),
    );
    // A short text fits, so only the always-on toggle puts a control on screen.
    await expectBoolKnobDistinct(
      tester,
      buildVotingExpandableTextCase,
      label: 'Toggle when text fits',
      otherKnobs: {
        'Text': votingExpandableTextLabel(VotingExpandableTextCase.short),
      },
    );

    Future<void> pumpText(Map<String, String> knobs) async {
      await pumpUseCase(tester, buildVotingExpandableTextCase, knobs: knobs);
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    await pumpText(const {});
    expect(find.text('View more'), findsOneWidget);
    await pumpText({
      'Controls': votingExpandableControlsLabel(
        VotingExpandableControlsCase.showDescription,
      ),
    });
    expect(find.text('Show description'), findsOneWidget);
    await pumpText({
      'Text': votingExpandableTextLabel(VotingExpandableTextCase.short),
    });
    expect(find.text('View more'), findsNothing);
    await pumpText({
      'Text': votingExpandableTextLabel(VotingExpandableTextCase.short),
      'Toggle when text fits': 'true',
    });
    expect(find.text('View more'), findsOneWidget);
    await pumpText({
      'Text': votingExpandableTextLabel(VotingExpandableTextCase.empty),
    });
    expect(find.text('View more'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('pane primitives cover every shared scroll surface', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingPanePrimitiveCase,
      label: 'Widget',
      optionLabels: VotingPanePrimitiveCase.values
          .map(votingPanePrimitiveLabel)
          .toList(),
    );

    Future<void> pumpPane(VotingPanePrimitiveCase primitive) async {
      await pumpUseCase(
        tester,
        buildVotingPanePrimitiveCase,
        knobs: {'Widget': votingPanePrimitiveLabel(primitive)},
      );
      expect(tester.takeException(), isNull, reason: '$primitive');
    }

    await pumpPane(VotingPanePrimitiveCase.loading);
    expect(find.byType(VotingPaneLoading), findsOneWidget);
    await pumpPane(VotingPanePrimitiveCase.stateView);
    expect(find.text('Home'), findsOneWidget);
    await pumpPane(VotingPanePrimitiveCase.listView);
    expect(find.text('Voting round 1'), findsOneWidget);
    await pumpPane(VotingPanePrimitiveCase.scrollView);
    expect(find.text('Section 1'), findsOneWidget);
    await pumpPane(VotingPanePrimitiveCase.centeredScrollView);
    expect(find.text('Centered pane content'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('mobile scaffold covers every route title and its padding', (
    tester,
  ) async {
    if (wbCompiledLaneLayout != WbLayout.mobile) {
      await pumpUseCase(tester, buildVotingMobileScaffoldCase);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
      await disposeTree(tester);
      return;
    }

    // No fingerprint sweep for the title: the serif nav title ellipsizes at
    // this width, and the test font draws every glyph as the same box, so two
    // truncated titles rasterise identically. The per-title finds below are
    // the distinguishing expectation.
    await expectBoolKnobDistinct(
      tester,
      buildVotingMobileScaffoldCase,
      label: 'Horizontal padding',
    );

    for (final title in VotingScaffoldTitleCase.values) {
      await pumpUseCase(
        tester,
        buildVotingMobileScaffoldCase,
        knobs: {'Title': votingScaffoldTitleLabel(title)},
      );
      expect(tester.takeException(), isNull, reason: '$title');
      expect(find.text(votingScaffoldTitleLabel(title)), findsOneWidget);
    }
    await disposeTree(tester);
  });

  testWidgets('active poll covers eligibility, answers, power and proposals', (
    tester,
  ) async {
    final lane = _lane;
    // Taller than the default canvas: the mobile frame sizes itself from the
    // MediaQuery, and a second proposal only fits below the phone fold.
    const tall = Size(1400, 2400);
    Future<void> expectActiveAxisDistinct(
      String label,
      List<String> optionLabels, {
      Map<String, String> otherKnobs = const {},
    }) async {
      final seen = <String, String>{};
      for (final option in optionLabels) {
        await pumpUseCase(
          tester,
          buildVotingActivePollCase,
          knobs: {'Layout': lane, ...otherKnobs, label: option},
          canvasSize: tall,
        );
        expect(tester.takeException(), isNull, reason: '$label / $option');
        final fingerprint = await useCaseFingerprint(tester);
        expect(seen[fingerprint], isNull, reason: "'$label' / $option");
        seen[fingerprint] = option;
      }
      await disposeTree(tester);
    }

    await expectActiveAxisDistinct(
      'Eligibility',
      VotingActivePollEligibility.values
          .map(votingActivePollEligibilityLabel)
          .toList(),
    );
    await expectActiveAxisDistinct(
      'Answers',
      VotingActivePollAnswers.values.map(votingActivePollAnswersLabel).toList(),
      // 'Some' only differs from 'All' once the round has a second proposal.
      otherKnobs: {
        'Proposals': votingActivePollProposalsLabel(
          VotingActivePollProposals.two,
        ),
      },
    );
    await expectActiveAxisDistinct(
      'Voting power',
      VotingActivePollPower.values.map(votingActivePollPowerLabel).toList(),
    );
    await expectActiveAxisDistinct(
      'Proposals',
      VotingActivePollProposals.values
          .map(votingActivePollProposalsLabel)
          .toList(),
    );
    await expectActiveAxisDistinct('Description', const ['true', 'false']);

    Future<void> pumpActive(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingActivePollCase,
        knobs: {'Layout': lane, ...knobs},
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    await pumpActive({
      'Proposals': votingActivePollProposalsLabel(
        VotingActivePollProposals.none,
      ),
    });
    expect(find.textContaining('No proposals'), findsOneWidget);
    await pumpActive({
      'Voting power': votingActivePollPowerLabel(
        VotingActivePollPower.preparing,
      ),
    });
    expect(find.text('Preparing voting power'), findsOneWidget);
    await pumpActive(const {'End date': 'false'});
    expect(find.text('Voting active'), findsOneWidget);
    await pumpActive(const {});
    expect(find.textContaining('A silly sample round'), findsOneWidget);
    await pumpActive(const {'Description': 'false'});
    expect(find.textContaining('A silly sample round'), findsNothing);
    await pumpActive({
      'Answers': votingActivePollAnswersLabel(VotingActivePollAnswers.all),
    });
    expect(find.text('Review answers'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('submit progress covers the step and viewport axes', (
    tester,
  ) async {
    for (final viewport in VotingSubmissionViewport.values) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingSubmitProgressCase,
        label: 'Step',
        optionLabels: VotingSubmissionProgressStep.values
            .map(votingSubmitStepLabel)
            .toList(),
        otherKnobs: {'Viewport': votingSubmitViewportLabel(viewport)},
      );
    }
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingSubmitProgressCase,
      label: 'Viewport',
      optionLabels: VotingSubmissionViewport.values
          .map(votingSubmitViewportLabel)
          .toList(),
    );
  });

  testWidgets('submit progress reports every ring value', (tester) async {
    // The ring tweens from zero over 220ms, so the first frame looks the same
    // for every fraction; the step's own semantics value is what the screen
    // computes from the prop.
    String? ringValue() {
      final rings = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where(
            (widget) =>
                widget.properties.label ==
                'Active voting submission step progress',
          );
      return rings.single.properties.value;
    }

    const expected = <VotingSubmissionProgressCase, String>{
      VotingSubmissionProgressCase.justStarted: '0%',
      VotingSubmissionProgressCase.quarter: '25%',
      VotingSubmissionProgressCase.mostOfTheWay: '60%',
      VotingSubmissionProgressCase.stepComplete: '100%',
      VotingSubmissionProgressCase.unknown: 'Unknown',
    };
    for (final entry in expected.entries) {
      await pumpUseCase(
        tester,
        buildVotingSubmitProgressCase,
        knobs: {'Progress': votingSubmitProgressLabel(entry.key)},
      );
      expect(tester.takeException(), isNull, reason: entry.key.name);
      expect(ringValue(), entry.value, reason: entry.key.name);
    }
    // 'Step default' is the passthrough: each step keeps the determinacy the
    // screen gives it in production, finalizing included.
    const perStep = <VotingSubmissionProgressStep, String>{
      VotingSubmissionProgressStep.provingAuthority: '25%',
      VotingSubmissionProgressStep.castingVotes: '60%',
      VotingSubmissionProgressStep.finalizing: 'Unknown',
    };
    for (final entry in perStep.entries) {
      await pumpUseCase(
        tester,
        buildVotingSubmitProgressCase,
        knobs: {
          'Progress': votingSubmitProgressLabel(
            VotingSubmissionProgressCase.stepDefault,
          ),
          'Step': votingSubmitStepLabel(entry.key),
        },
      );
      expect(tester.takeException(), isNull, reason: entry.key.name);
      expect(ringValue(), entry.value, reason: entry.key.name);
    }
    await disposeTree(tester);
  });

  testWidgets('Keystone signing registers each layout\'s own knobs', (
    tester,
  ) async {
    final desktop = await pumpUseCase(
      tester,
      buildVotingKeystoneSigningGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.desktop)},
    );
    expect(desktop.knobs.keys.toSet(), {
      'Layout',
      'QR',
      'Bundles',
      'Memos',
      'Scan error',
      'Skip action',
    });

    final mobile = await pumpUseCase(
      tester,
      buildVotingKeystoneSigningGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
    );
    expect(mobile.knobs.keys.toSet(), {
      'Layout',
      'Stage',
      'Bundles',
      'Memos',
      'Skip action',
    });
    // The mobile screen's own badge, so the mobile branch is the one rendering.
    expect(find.text('2 of 3 remaining bundles'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('Keystone signing covers the request and scanner stages', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingKeystoneSigningCase,
      label: 'Stage',
      optionLabels: VotingKeystoneStage.values
          .map(votingKeystoneStageLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingKeystoneSigningCase,
      label: 'Memos',
      optionLabels: VotingMobileKeystoneMemos.values
          .map(votingMobileKeystoneMemosLabel)
          .toList(),
    );
  });

  testWidgets('Keystone signing covers the bundle count and the skip action', (
    tester,
  ) async {
    Future<void> pumpRequest(Map<String, String> knobs) async {
      await pumpUseCase(tester, buildVotingKeystoneSigningCase, knobs: knobs);
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    // The screen turns the bundle counts into its context badge, and no count
    // at all drops the badge.
    await pumpRequest({
      'Bundles': votingMobileKeystoneBundlesLabel(
        VotingMobileKeystoneBundles.single,
      ),
    });
    expect(find.text('1 voting bundle'), findsOneWidget);
    await pumpRequest({
      'Bundles': votingMobileKeystoneBundlesLabel(
        VotingMobileKeystoneBundles.batch,
      ),
    });
    expect(find.text('2 of 3 remaining bundles'), findsOneWidget);
    await pumpRequest({
      'Bundles': votingMobileKeystoneBundlesLabel(
        VotingMobileKeystoneBundles.uncounted,
      ),
    });
    expect(find.text('1 voting bundle'), findsNothing);
    expect(find.text('2 of 3 remaining bundles'), findsNothing);

    await pumpRequest(const {});
    expect(find.text('Skip unsigned bundles'), findsOneWidget);
    await pumpRequest(const {'Skip action': 'false'});
    expect(find.text('Skip unsigned bundles'), findsNothing);

    await pumpRequest({
      'Memos': votingMobileKeystoneMemosLabel(VotingMobileKeystoneMemos.none),
    });
    expect(find.textContaining('Bundle 1 of 3'), findsNothing);
    await pumpRequest({
      'Memos': votingMobileKeystoneMemosLabel(VotingMobileKeystoneMemos.one),
    });
    expect(find.text('Bundle 1 of 3'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('voted poll previews only the compiled lane', (tester) async {
    // Taller than the default canvas: the share-status card sits at the end of
    // the voted content, below the fold of the mobile scaffold.
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    Future<String> pumpVoted(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingVotedPollCase,
        knobs: {'Layout': lane, ...knobs},
        canvasSize: const Size(1400, 2400),
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
      return useCaseFingerprint(tester);
    }

    Future<void> expectVotedAxisDistinct(
      String label,
      List<String> optionLabels,
    ) async {
      final seen = <String, String>{};
      for (final option in optionLabels) {
        final fingerprint = await pumpVoted({label: option});
        expect(seen[fingerprint], isNull, reason: "'$label' / $option");
        seen[fingerprint] = option;
      }
    }

    await expectVotedAxisDistinct(
      'Answers',
      VotingVotedPollAnswers.values.map(votingVotedPollAnswersLabel).toList(),
    );
    await expectVotedAxisDistinct(
      'Voted at',
      VotingVotedPollVotedAt.values.map(votingVotedPollVotedAtLabel).toList(),
    );
    await expectVotedAxisDistinct(
      'Voting power',
      VotingVotedPollPower.values.map(votingVotedPollPowerLabel).toList(),
    );
    await expectVotedAxisDistinct(
      'Proposals',
      VotingVotedPollProposals.values
          .map(votingVotedPollProposalsLabel)
          .toList(),
    );

    await pumpVoted({
      'Answers': votingVotedPollAnswersLabel(
        VotingVotedPollAnswers.someSkipped,
      ),
    });
    // The desktop card puts the status in its own badge; the mobile card
    // folds it into the metadata rich text.
    expect(find.textContaining('Skipped'), findsOneWidget);
    // The two headers word the same states differently: the desktop meta row
    // drops the value, the mobile receipt rows spell it out.
    final desktopLane = wbCompiledLaneLayout == WbLayout.desktop;
    await pumpVoted({
      'Voted at': votingVotedPollVotedAtLabel(
        VotingVotedPollVotedAt.notAvailable,
      ),
    });
    expect(
      desktopLane ? find.text('Voted') : find.text('Not available'),
      findsWidgets,
    );
    await pumpVoted({
      'Voting power': votingVotedPollPowerLabel(VotingVotedPollPower.preparing),
    });
    expect(
      desktopLane
          ? find.text('Preparing voting power')
          : find.text('Preparing...'),
      findsOneWidget,
    );

    final other = wbCompiledLaneLayout == WbLayout.desktop
        ? WbLayout.mobile
        : WbLayout.desktop;
    await pumpUseCase(
      tester,
      buildVotingVotedPollCase,
      knobs: {'Layout': wbLayoutLabel(other)},
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('extracted fixture delegates keep their builder parameters', (
    tester,
  ) async {
    // The compact submission viewport is the only fixture parameter the
    // extraction could silently drop, and the desktop voted shell is the only
    // frame that is not a mobile scaffold.
    await pumpUseCase(tester, buildMobileVotingSubmissionCastingCompactUseCase);
    expect(tester.takeException(), isNull);
    final compactViewport = tester.widget<MediaQuery>(
      find
          .ancestor(
            of: find.byType(MobileVotingSubmissionProgressScreen),
            matching: find.byType(MediaQuery),
          )
          .first,
    );
    expect(
      compactViewport.data.size,
      const Size(375, 667),
      reason: 'compact viewport lost',
    );
    expect(
      compactViewport.data.padding,
      const EdgeInsets.only(top: 47, bottom: 34),
      reason: 'compact safe area lost',
    );

    await pumpUseCase(tester, buildDesktopVotingVotedUseCase);
    expect(tester.takeException(), isNull);
    expect(find.text('Vote'), findsWidgets, reason: 'desktop shell lost');
    await disposeTree(tester);
  });

  testWidgets('review covers session, eligibility and answer axes', (
    tester,
  ) async {
    final lane = wbLayoutLabel(wbCompiledLaneLayout);
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingReviewCase,
      label: 'Session',
      optionLabels: VotingReviewSessionCase.values
          .map(votingReviewSessionLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingReviewCase,
      label: 'Eligibility',
      optionLabels: VotingReviewEligibilityCase.values
          .map(votingReviewEligibilityLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingReviewCase,
      label: 'Answers',
      optionLabels: VotingReviewAnswersCase.values
          .map(votingReviewAnswersLabel)
          .toList(),
      otherKnobs: {'Layout': lane},
    );

    Future<void> pumpReview(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingReviewCase,
        knobs: {'Layout': lane, ...knobs},
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    await pumpReview({
      'Answers': votingReviewAnswersLabel(VotingReviewAnswersCase.someSkipped),
    });
    // The desktop card puts the status in its own badge; the mobile card
    // folds it into the metadata rich text.
    expect(find.textContaining('Skipped'), findsOneWidget);
    await pumpReview({
      'Answers': votingReviewAnswersLabel(VotingReviewAnswersCase.none),
    });
    expect(
      find.text('Choose at least one option before submitting.'),
      findsOneWidget,
    );
    await pumpReview({
      'Eligibility': votingReviewEligibilityLabel(
        VotingReviewEligibilityCase.preparing,
      ),
    });
    expect(find.text('Preparing voting power.'), findsOneWidget);
    await pumpReview({
      'Eligibility': votingReviewEligibilityLabel(
        VotingReviewEligibilityCase.unavailable,
      ),
    });
    expect(find.text('Voting power unavailable.'), findsOneWidget);
    await pumpReview({
      'Session': votingReviewSessionLabel(VotingReviewSessionCase.failed),
    });
    expect(find.textContaining("Couldn't load review"), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('review previews the other layout only in its own lane', (
    tester,
  ) async {
    final other = wbCompiledLaneLayout == WbLayout.desktop
        ? WbLayout.mobile
        : WbLayout.desktop;
    await pumpUseCase(
      tester,
      buildVotingReviewCase,
      knobs: {'Layout': wbLayoutLabel(other)},
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('submit status covers step, account, problem and progress', (
    tester,
  ) async {
    final desktop = _lane;
    if (_desktopLane) {
      // The mobile progress screen reads only the active step, so the two
      // steps before delegation collapse into one render there; the per-step
      // expectations below still run in both lanes.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingStatusCase,
        label: 'Step',
        optionLabels: VotingStatusStepCase.values
            .map(votingStatusStepLabel)
            .toList(),
        otherKnobs: {'Layout': desktop},
      );
    }
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingStatusCase,
      label: 'Problem',
      optionLabels: VotingStatusProblemCase.values
          .map(votingStatusProblemLabel)
          .toList(),
      otherKnobs: {'Layout': desktop},
    );
    if (_desktopLane) {
      // The mobile screen swaps in its Keystone screen only once the session
      // reaches the signing phase, which this fixture never enters, so the
      // hardware flag is a desktop-only difference here.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingStatusCase,
        label: 'Account',
        optionLabels: VotingStatusAccountCase.values
            .map(votingStatusAccountLabel)
            .toList(),
        otherKnobs: {'Layout': desktop},
      );
    }
    if (_desktopLane) {
      // The question count lives in `_StatusContent`; the mobile progress
      // screen draws the same bar for both.
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingStatusCase,
        label: 'Vote progress',
        optionLabels: VotingStatusVoteProgressCase.values
            .map(votingStatusVoteProgressLabel)
            .toList(),
        otherKnobs: {
          'Layout': desktop,
          'Step': votingStatusStepLabel(VotingStatusStepCase.castingVotes),
        },
      );
    }
    if (_desktopLane) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingStatusCase,
        label: 'Layout',
        optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      );
    }

    Future<void> pumpStatus(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingStatusCase,
        knobs: {'Layout': desktop, ...knobs},
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    if (_desktopLane) {
      // Step detail and the hardware line belong to `_StatusContent`; the
      // mobile lane routes these steps to the mobile progress screen instead.
      await pumpStatus({
        'Step': votingStatusStepLabel(
          VotingStatusStepCase.waitingForWalletSync,
        ),
      });
      expect(find.text('Waiting for wallet sync'), findsOneWidget);
      expect(find.text('3600 blocks remaining'), findsOneWidget);
      await pumpStatus({
        'Step': votingStatusStepLabel(VotingStatusStepCase.castingVotes),
      });
      expect(find.text('Casting votes and submitting shares'), findsOneWidget);
      await pumpStatus({
        'Account': votingStatusAccountLabel(VotingStatusAccountCase.keystone),
      });
      expect(find.text('Signing with Keystone'), findsOneWidget);
    } else {
      await pumpStatus(const {});
      expect(find.byType(MobileVotingSubmissionProgressScreen), findsOneWidget);
    }
    await pumpStatus({
      'Problem': votingStatusProblemLabel(
        VotingStatusProblemCase.softwareAccountRequired,
      ),
    });
    expect(find.text('Software account required'), findsOneWidget);
    await pumpStatus({
      'Problem': votingStatusProblemLabel(
        VotingStatusProblemCase.jobFailedClearable,
      ),
    });
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await pumpStatus({
      'Problem': votingStatusProblemLabel(VotingStatusProblemCase.jobFailed),
    });
    expect(find.text('Clear'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await pumpStatus({
      'Problem': votingStatusProblemLabel(
        VotingStatusProblemCase.couldNotStart,
      ),
    });
    expect(
      find.text("Couldn't start the voting session for this account."),
      findsOneWidget,
    );
    // Each PIR option has to reach its own branch of the session's snapshot
    // failure line, not the generic one.
    const pirLines = <VotingStatusProblemCase, String>{
      VotingStatusProblemCase.pirDataBehind: 'PIR endpoints report 3,543,100',
      VotingStatusProblemCase.pirDataAhead:
          'Configured PIR endpoints are ahead',
      VotingStatusProblemCase.pirUnreachable:
          "Couldn't reach any configured PIR endpoint",
      // The diagnostics tail keeps the fixture bound to `_pirDiagnosticLog`.
      VotingStatusProblemCase.pirNoMatch: 'status=malformedJson',
    };
    for (final entry in pirLines.entries) {
      await pumpStatus({'Problem': votingStatusProblemLabel(entry.key)});
      expect(
        find.textContaining(entry.value),
        findsOneWidget,
        reason: entry.key.name,
      );
    }
    await disposeTree(tester);
  });

  testWidgets('desktop Keystone signing covers every panel axis', (
    tester,
  ) async {
    if (!_desktopLane) {
      // Desktop-only panel: the mobile lane gets the run-command notice.
      await pumpUseCase(tester, buildVotingDesktopKeystoneSigningCase);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
      await disposeTree(tester);
      return;
    }
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingDesktopKeystoneSigningCase,
      label: 'QR',
      optionLabels: VotingKeystoneQrCase.values
          .map(votingKeystoneQrLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingDesktopKeystoneSigningCase,
      label: 'Memos',
      optionLabels: VotingKeystoneMemosCase.values
          .map(votingKeystoneMemosLabel)
          .toList(),
    );
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingDesktopKeystoneSigningCase,
      label: 'Bundles',
      optionLabels: VotingKeystoneBundlesCase.values
          .map(votingKeystoneBundlesLabel)
          .toList(),
    );

    Future<void> pumpPanel(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingDesktopKeystoneSigningCase,
        knobs: knobs,
      );
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    await pumpPanel(const {});
    expect(find.text('Sign 1 voting bundle'), findsOneWidget);
    expect(find.text('One Keystone approval'), findsOneWidget);
    await pumpPanel({
      'Bundles': votingKeystoneBundlesLabel(VotingKeystoneBundlesCase.batch),
    });
    expect(find.text('Sign 2 voting bundles'), findsOneWidget);
    expect(find.text('This QR signs 2 of 3 remaining bundles'), findsOneWidget);
    await pumpPanel(const {'Scan error': 'true'});
    expect(
      find.text('That QR was not a signed voting response. Try again.'),
      findsOneWidget,
    );
    await pumpPanel(const {'Bundles': '2 of 3 bundles', 'Skip action': 'true'});
    expect(find.text('Skip'), findsOneWidget);
    await pumpPanel(const {'Bundles': '2 of 3 bundles'});
    expect(find.text('Skip'), findsNothing);
    await pumpPanel({
      'Memos': votingKeystoneMemosLabel(VotingKeystoneMemosCase.pager),
    });
    expect(find.byKey(const ValueKey('keystone_memo_next')), findsOneWidget);
    await pumpPanel({
      'Memos': votingKeystoneMemosLabel(VotingKeystoneMemosCase.none),
    });
    expect(find.byKey(const ValueKey('keystone_memo_next')), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('submission confirmation covers session and outcome', (
    tester,
  ) async {
    final desktop = _lane;
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingConfirmationCase,
      label: 'Outcome',
      optionLabels: VotingConfirmationOutcomeCase.values
          .map(votingConfirmationOutcomeLabel)
          .toList(),
      otherKnobs: {'Layout': desktop},
    );
    if (_desktopLane) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingConfirmationCase,
        label: 'Layout',
        optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      );
    }

    Future<void> pumpConfirmation(Map<String, String> knobs) async {
      await pumpUseCase(
        tester,
        buildVotingConfirmationCase,
        knobs: {'Layout': desktop, ...knobs},
      );
      // The eligibility refresh and the cached-receipt failure both land in
      // the frame after mount, and the mobile submitted screen arms a
      // success-haptics fallback timer that has to fire before teardown.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull, reason: '$knobs');
    }

    await pumpConfirmation(const {});
    // The confirmed state is the one place the two form factors diverge: the
    // mobile screen hands it to `MobileVotingSubmittedScreen`.
    expect(
      _desktopLane ? find.text('Submission confirmed!') : find.text('Voted'),
      findsOneWidget,
    );
    await pumpConfirmation({
      'Outcome': votingConfirmationOutcomeLabel(
        VotingConfirmationOutcomeCase.notComplete,
      ),
    });
    expect(find.text('Submission not complete'), findsOneWidget);
    expect(
      find.text(
        'This account has not completed submission for this voting round.',
      ),
      findsOneWidget,
    );
    await pumpConfirmation({
      'Outcome': votingConfirmationOutcomeLabel(
        VotingConfirmationOutcomeCase.checkingEligibility,
      ),
    });
    expect(
      find.text('Checking voting eligibility for this account.'),
      findsOneWidget,
    );
    await pumpConfirmation({
      'Outcome': votingConfirmationOutcomeLabel(
        VotingConfirmationOutcomeCase.eligibilityNotConfirmed,
      ),
    });
    expect(
      find.text('Voting eligibility has not been confirmed for this account.'),
      findsOneWidget,
    );
    await pumpConfirmation({
      'Outcome': votingConfirmationOutcomeLabel(
        VotingConfirmationOutcomeCase.refreshFailed,
      ),
    });
    expect(find.text('Retry'), findsOneWidget);
    // A load failure only changes what the screen says once eligibility is
    // unconfirmed: a confirmed receipt survives it unchanged.
    final unconfirmed = votingConfirmationOutcomeLabel(
      VotingConfirmationOutcomeCase.eligibilityNotConfirmed,
    );
    await pumpConfirmation({
      'Outcome': unconfirmed,
      'Session': votingConfirmationSessionLabel(
        VotingConfirmationSessionCase.failedWithoutReceipt,
      ),
    });
    expect(
      find.textContaining("Couldn't load submission details"),
      findsOneWidget,
    );
    expect(find.text('Voting round'), findsOneWidget);
    await pumpConfirmation({
      'Outcome': unconfirmed,
      'Session': votingConfirmationSessionLabel(
        VotingConfirmationSessionCase.failedWithReceipt,
      ),
    });
    expect(
      find.textContaining('the voting service did not respond.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    await pumpConfirmation({
      'Outcome': unconfirmed,
      'Session': votingConfirmationSessionLabel(
        VotingConfirmationSessionCase.loading,
      ),
    });
    expect(find.text('Voting round'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('account guard covers both layouts and both account states', (
    tester,
  ) async {
    await expectKnobOptionsRenderDistinctly(
      tester,
      buildVotingAccountGuardCase,
      label: 'Account',
      optionLabels: VotingGuardAccountCase.values
          .map(votingGuardAccountLabel)
          .toList(),
      otherKnobs: {'Layout': _lane},
    );
    if (_desktopLane) {
      await expectKnobOptionsRenderDistinctly(
        tester,
        buildVotingAccountGuardCase,
        label: 'Layout',
        optionLabels: WbLayout.values.map(wbLayoutLabel).toList(),
      );

      await pumpUseCase(
        tester,
        buildVotingAccountGuardCase,
        knobs: {
          'Layout': 'Desktop',
          'Account': votingGuardAccountLabel(VotingGuardAccountCase.failed),
        },
      );
      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load account"), findsOneWidget);
    }

    await pumpUseCase(
      tester,
      buildVotingAccountGuardCase,
      knobs: {
        'Layout': 'Mobile',
        'Account': votingGuardAccountLabel(VotingGuardAccountCase.failed),
      },
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining("Couldn't load account."), findsOneWidget);
    await disposeTree(tester);
  });
}
