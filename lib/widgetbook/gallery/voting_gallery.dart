// ignore_for_file: depend_on_referenced_packages
// widgetbook is dev-only; see `widgetbook.dart` for the boundary.

import 'package:flutter/widgets.dart';
import 'package:widgetbook/widgetbook.dart';

import '../../src/features/voting/screens/voting_status_screen.dart';
import '../support/wb_layout.dart';
import '../support/wb_state.dart';
import '../voting_screen_use_cases.dart';
import '../voting_use_cases.dart';

/// The Voting gallery: one use case per surface, dispatching to the fixtures
/// in `voting_use_cases.dart` (mobile widget classes, none of them registered
/// before) and `voting_screen_use_cases.dart` (the screens driven through
/// provider overrides, which carry a `Layout` knob for both form factors).
///
/// The remaining surfaces here are mobile widget classes whose desktop twin
/// has no fixture yet.
final List<WidgetbookNode> votingGalleryNodes = [
  WidgetbookComponent(
    name: 'Voting polls',
    useCases: [
      WidgetbookUseCase(name: 'Poll list', builder: buildVotingPollListCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Voting proposal detail',
    useCases: [
      WidgetbookUseCase(
        name: 'Detail screen',
        builder: buildVotingProposalDetailCase,
      ),
      WidgetbookUseCase(
        name: 'Active poll',
        builder: buildVotingActivePollCase,
      ),
      WidgetbookUseCase(name: 'Voted poll', builder: buildVotingVotedPollCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Voting review',
    useCases: [
      WidgetbookUseCase(name: 'Review', builder: buildVotingReviewCase),
    ],
  ),
  WidgetbookComponent(
    name: 'Voting submit',
    useCases: [
      WidgetbookUseCase(name: 'Status', builder: buildVotingStatusCase),
      WidgetbookUseCase(
        name: 'Progress',
        builder: buildVotingSubmitProgressCase,
      ),
      WidgetbookUseCase(
        name: 'Keystone signing',
        builder: buildVotingKeystoneSigningGalleryCase,
      ),
      WidgetbookUseCase(
        name: 'Submitted',
        builder: buildMobileVotingSubmittedUseCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Voting confirmation',
    useCases: [
      WidgetbookUseCase(
        name: 'Confirmation',
        builder: buildVotingConfirmationCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Voting guards',
    useCases: [
      WidgetbookUseCase(
        name: 'Account guard',
        builder: buildVotingAccountGuardCase,
      ),
    ],
  ),
  WidgetbookComponent(
    name: 'Voting results',
    useCases: [
      WidgetbookUseCase(name: 'Results', builder: buildVotingResultsCase),
    ],
  ),
  WidgetbookFolder(
    name: 'Components',
    children: [
      WidgetbookComponent(
        name: 'Voting poll card',
        useCases: [
          WidgetbookUseCase(
            name: 'Poll card',
            builder: buildVotingPollCardCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Voting cards',
        useCases: [
          WidgetbookUseCase(
            name: 'Proposal card',
            builder: buildVotingProposalCardCase,
          ),
          WidgetbookUseCase(
            name: 'Result card',
            builder: buildVotingResultCardCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Voting expandable text',
        useCases: [
          WidgetbookUseCase(
            name: 'Expandable text',
            builder: buildVotingExpandableTextCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Voting pane',
        useCases: [
          WidgetbookUseCase(
            name: 'Pane primitives',
            builder: buildVotingPanePrimitiveCase,
          ),
        ],
      ),
      WidgetbookComponent(
        name: 'Voting scaffold',
        useCases: [
          WidgetbookUseCase(
            name: 'Mobile scaffold',
            builder: buildVotingMobileScaffoldCase,
          ),
        ],
      ),
    ],
  ),
  WidgetbookFolder(
    name: 'Modals',
    children: [
      WidgetbookComponent(
        name: 'Voting modals',
        useCases: [
          WidgetbookUseCase(
            name: 'Settings sheet',
            builder: buildVotingSettingsSheetCase,
          ),
          WidgetbookUseCase(
            name: 'Ineligible dialog',
            builder: buildVotingIneligibleDialogCase,
          ),
          WidgetbookUseCase(
            name: 'Skipped questions dialog',
            builder: buildVotingSkippedQuestionsDialogCase,
          ),
          WidgetbookUseCase(
            name: 'Skip signed bundles dialog',
            builder: buildVotingSkipSignedBundlesDialogCase,
          ),
        ],
      ),
    ],
  ),
];

// --- Voting polls ----------------------------------------------------------

Widget buildVotingPollListCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final rounds = wbStateKnob<VotingPollRoundsCase>(
    context,
    label: 'Rounds',
    options: VotingPollRoundsCase.values,
    labelBuilder: votingPollRoundsLabel,
  );
  final load = wbStateKnob<VotingPollLoadCase>(
    context,
    label: 'Load',
    options: VotingPollLoadCase.values,
    labelBuilder: votingPollLoadLabel,
  );
  return votingPollListFixture(layout: layout, rounds: rounds, load: load);
}

String votingPollRoundsLabel(VotingPollRoundsCase rounds) {
  return switch (rounds) {
    VotingPollRoundsCase.rounds => 'Active, voted, closed',
    VotingPollRoundsCase.mixedEligibility => 'Mixed eligibility',
    VotingPollRoundsCase.snapshotUsed => 'Snapshot already used',
    VotingPollRoundsCase.empty => 'No rounds',
  };
}

String votingPollLoadLabel(VotingPollLoadCase load) {
  return switch (load) {
    VotingPollLoadCase.loaded => 'Loaded',
    VotingPollLoadCase.loading => 'Loading',
    VotingPollLoadCase.failed => "Couldn't load",
  };
}

// --- Voting poll card ------------------------------------------------------

Widget buildVotingPollCardCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final status = wbStateKnob<VotingPollCardState>(
    context,
    label: 'Status',
    options: VotingPollCardState.values,
    // Active is the state the other axes are readable in: only an active card
    // reads eligibility.
    initial: VotingPollCardState.active,
    labelBuilder: votingPollCardStateLabel,
  );
  final date = wbStateKnob<VotingPollCardDate>(
    context,
    label: 'Date',
    options: VotingPollCardDate.values,
    labelBuilder: votingPollCardDateLabel,
  );
  final eligibility = wbStateKnob<VotingPollCardEligibility>(
    context,
    label: 'Eligibility',
    options: votingPollCardEligibilityOptions,
    labelBuilder: votingPollCardEligibilityLabel,
  );
  final forumLink = wbBoolKnob(context, label: 'Forum link', initial: true);
  final emptyText = wbBoolKnob(context, label: 'Empty title and description');
  return votingPollCardFixture(
    layout: layout,
    state: status,
    date: date,
    eligibility: eligibility,
    forumLink: forumLink,
    emptyText: emptyText,
  );
}

String votingPollCardStateLabel(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress => 'In progress',
    VotingPollCardState.active => 'Active',
    VotingPollCardState.voted => 'Voted',
    VotingPollCardState.tallying => 'Tallying',
    VotingPollCardState.closed => 'Closed',
  };
}

String votingPollCardDateLabel(VotingPollCardDate date) {
  return switch (date) {
    VotingPollCardDate.endDate => 'End date',
    VotingPollCardDate.startDate => 'Start date',
    VotingPollCardDate.none => 'No date',
  };
}

/// A check that is still running or failed must never read as ineligible, so
/// both render the eligible card and are not knob options of their own.
const votingPollCardEligibilityOptions = [
  VotingPollCardEligibility.eligible,
  VotingPollCardEligibility.ineligible,
  VotingPollCardEligibility.alreadyUsed,
];

String votingPollCardEligibilityLabel(VotingPollCardEligibility eligibility) {
  return switch (eligibility) {
    VotingPollCardEligibility.eligible => 'Eligible',
    VotingPollCardEligibility.ineligible => 'Not eligible',
    VotingPollCardEligibility.alreadyUsed => 'Already used',
    VotingPollCardEligibility.checking => 'Checking',
    VotingPollCardEligibility.checkFailed => 'Check failed',
  };
}

// --- Voting proposal detail ------------------------------------------------

Widget buildVotingProposalDetailCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final session = wbStateKnob<VotingDetailSessionCase>(
    context,
    label: 'Session',
    options: VotingDetailSessionCase.values,
    labelBuilder: votingDetailSessionLabel,
  );
  final branch = wbStateKnob<VotingDetailBranchCase>(
    context,
    label: 'Content',
    options: VotingDetailBranchCase.values,
    labelBuilder: votingDetailBranchLabel,
  );
  final power = wbStateKnob<VotingDetailPowerCase>(
    context,
    label: 'Voting power',
    options: VotingDetailPowerCase.values,
    labelBuilder: votingDetailPowerLabel,
  );
  // Every content branch takes its layout from `kAppFormFactor`, so the knob
  // only swaps the shell around it.
  return WbLaneOnly(
    layout: layout,
    child: votingProposalDetailFixture(
      layout: layout,
      session: session,
      branch: branch,
      power: power,
    ),
  );
}

String votingDetailSessionLabel(VotingDetailSessionCase session) {
  return switch (session) {
    VotingDetailSessionCase.loaded => 'Loaded',
    VotingDetailSessionCase.loading => 'Loading',
    VotingDetailSessionCase.failed => "Couldn't load round",
    VotingDetailSessionCase.roundUnavailable => 'Round unavailable',
  };
}

String votingDetailBranchLabel(VotingDetailBranchCase branch) {
  return switch (branch) {
    VotingDetailBranchCase.activePoll => 'Active poll',
    VotingDetailBranchCase.voted => 'Voted',
    VotingDetailBranchCase.voteInProgress => 'Vote in progress',
    VotingDetailBranchCase.redirectToResults => 'Redirect to results',
  };
}

String votingDetailPowerLabel(VotingDetailPowerCase power) {
  return switch (power) {
    VotingDetailPowerCase.ready => 'Ready',
    VotingDetailPowerCase.preparing => 'Preparing',
    VotingDetailPowerCase.unavailable => 'Unavailable',
  };
}

/// Eligibility outcomes the active-poll fixture covers.
enum VotingActivePollEligibility {
  eligible,
  ineligible,
  privacyTrim,
  checkFailed,
  snapshotUsed,
}

Widget buildVotingActivePollCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final eligibility = wbStateKnob<VotingActivePollEligibility>(
    context,
    label: 'Eligibility',
    options: VotingActivePollEligibility.values,
    labelBuilder: votingActivePollEligibilityLabel,
  );
  final answers = wbStateKnob<VotingActivePollAnswers>(
    context,
    label: 'Answers',
    options: VotingActivePollAnswers.values,
    labelBuilder: votingActivePollAnswersLabel,
  );
  final power = wbStateKnob<VotingActivePollPower>(
    context,
    label: 'Voting power',
    options: VotingActivePollPower.values,
    labelBuilder: votingActivePollPowerLabel,
  );
  final proposals = wbStateKnob<VotingActivePollProposals>(
    context,
    label: 'Proposals',
    options: VotingActivePollProposals.values,
    labelBuilder: votingActivePollProposalsLabel,
  );
  final deadline = wbBoolKnob(context, label: 'End date', initial: true);
  final description = wbBoolKnob(context, label: 'Description', initial: true);
  // `VotingActivePollContent` picks its own layout from `kAppFormFactor`.
  return WbLaneOnly(
    layout: layout,
    child: votingActivePollFixture(
      context,
      frame: layout == WbLayout.mobile
          ? VotingActivePollFrame.mobile
          : VotingActivePollFrame.desktop,
      eligible:
          eligibility == VotingActivePollEligibility.eligible ||
          eligibility == VotingActivePollEligibility.privacyTrim,
      eligibilityUnknown:
          eligibility == VotingActivePollEligibility.checkFailed,
      previouslyUsed: eligibility == VotingActivePollEligibility.snapshotUsed,
      votingEligibilityMessage: switch (eligibility) {
        VotingActivePollEligibility.privacyTrim =>
          '0.125 ZEC is left out of this vote '
              'to keep your submission less identifiable.',
        VotingActivePollEligibility.checkFailed =>
          'Unable to check voting eligibility.',
        _ => null,
      },
      power: power,
      answers: answers,
      proposals: proposals,
      showDescription: description,
      showEndDate: deadline,
    ),
  );
}

String votingActivePollEligibilityLabel(VotingActivePollEligibility value) {
  return switch (value) {
    VotingActivePollEligibility.eligible => 'Eligible',
    VotingActivePollEligibility.ineligible => 'Not eligible',
    VotingActivePollEligibility.privacyTrim => 'Voting power trimmed',
    VotingActivePollEligibility.checkFailed => 'Eligibility check failed',
    VotingActivePollEligibility.snapshotUsed => 'Snapshot already used',
  };
}

String votingActivePollAnswersLabel(VotingActivePollAnswers answers) {
  return switch (answers) {
    VotingActivePollAnswers.none => 'None chosen',
    VotingActivePollAnswers.some => 'Some answered',
    VotingActivePollAnswers.all => 'All answered',
  };
}

String votingActivePollPowerLabel(VotingActivePollPower power) {
  return switch (power) {
    VotingActivePollPower.amount => 'Amount',
    VotingActivePollPower.preparing => 'Preparing',
    VotingActivePollPower.unavailable => 'Unavailable',
  };
}

String votingActivePollProposalsLabel(VotingActivePollProposals proposals) {
  return switch (proposals) {
    VotingActivePollProposals.one => 'One',
    VotingActivePollProposals.two => 'Two',
    VotingActivePollProposals.three => 'Three',
    VotingActivePollProposals.none => 'None',
  };
}

Widget buildVotingVotedPollCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final answers = wbStateKnob<VotingVotedPollAnswers>(
    context,
    label: 'Answers',
    options: VotingVotedPollAnswers.values,
    labelBuilder: votingVotedPollAnswersLabel,
  );
  final votedAt = wbStateKnob<VotingVotedPollVotedAt>(
    context,
    label: 'Voted at',
    options: VotingVotedPollVotedAt.values,
    labelBuilder: votingVotedPollVotedAtLabel,
  );
  final power = wbStateKnob<VotingVotedPollPower>(
    context,
    label: 'Voting power',
    options: VotingVotedPollPower.values,
    labelBuilder: votingVotedPollPowerLabel,
  );
  final proposals = wbStateKnob<VotingVotedPollProposals>(
    context,
    label: 'Proposals',
    options: VotingVotedPollProposals.values,
    labelBuilder: votingVotedPollProposalsLabel,
  );
  // `VotingVotedPollContent` takes its metrics from `kAppFormFactor`, so the
  // off-lane preview would be this lane's tokens in the other lane's shell.
  return WbLaneOnly(
    layout: layout,
    child: votingVotedPollFixture(
      frame: layout == WbLayout.mobile
          ? VotingVotedPollFrame.mobile
          : VotingVotedPollFrame.desktop,
      answers: answers,
      votedAt: votedAt,
      power: power,
      proposals: proposals,
    ),
  );
}

String votingVotedPollAnswersLabel(VotingVotedPollAnswers answers) {
  return switch (answers) {
    VotingVotedPollAnswers.allAnswered => 'All answered',
    VotingVotedPollAnswers.someSkipped => 'Some skipped',
  };
}

String votingVotedPollVotedAtLabel(VotingVotedPollVotedAt votedAt) {
  return switch (votedAt) {
    VotingVotedPollVotedAt.date => 'Date',
    VotingVotedPollVotedAt.notAvailable => 'Not available',
  };
}

String votingVotedPollPowerLabel(VotingVotedPollPower power) {
  return switch (power) {
    VotingVotedPollPower.amount => 'Amount',
    VotingVotedPollPower.preparing => 'Preparing',
    VotingVotedPollPower.notAvailable => 'Not available',
  };
}

String votingVotedPollProposalsLabel(VotingVotedPollProposals proposals) {
  return switch (proposals) {
    VotingVotedPollProposals.some => 'Some',
    VotingVotedPollProposals.none => 'None',
  };
}

// --- Voting review ---------------------------------------------------------

Widget buildVotingReviewCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final session = wbStateKnob<VotingReviewSessionCase>(
    context,
    label: 'Session',
    options: VotingReviewSessionCase.values,
    labelBuilder: votingReviewSessionLabel,
  );
  final eligibility = wbStateKnob<VotingReviewEligibilityCase>(
    context,
    label: 'Eligibility',
    options: VotingReviewEligibilityCase.values,
    labelBuilder: votingReviewEligibilityLabel,
  );
  final answers = wbStateKnob<VotingReviewAnswersCase>(
    context,
    label: 'Answers',
    options: VotingReviewAnswersCase.values,
    labelBuilder: votingReviewAnswersLabel,
  );
  // `VotingProposalCard` swaps implementations on `kAppFormFactor`, and the
  // desktop card overflows the phone box on a skipped proposal.
  return WbLaneOnly(
    layout: layout,
    child: votingReviewFixture(
      layout: layout,
      session: session,
      eligibility: eligibility,
      answers: answers,
    ),
  );
}

String votingReviewSessionLabel(VotingReviewSessionCase session) {
  return switch (session) {
    VotingReviewSessionCase.loaded => 'Loaded',
    VotingReviewSessionCase.loading => 'Loading',
    VotingReviewSessionCase.failed => "Couldn't load review",
  };
}

String votingReviewEligibilityLabel(VotingReviewEligibilityCase eligibility) {
  return switch (eligibility) {
    VotingReviewEligibilityCase.confirmed => 'Confirmed',
    VotingReviewEligibilityCase.preparing => 'Preparing voting power',
    VotingReviewEligibilityCase.unavailable => 'Voting power unavailable',
    VotingReviewEligibilityCase.failed => 'Eligibility error',
  };
}

String votingReviewAnswersLabel(VotingReviewAnswersCase answers) {
  return switch (answers) {
    VotingReviewAnswersCase.allAnswered => 'All answered',
    VotingReviewAnswersCase.someSkipped => 'Some skipped',
    VotingReviewAnswersCase.none => 'None chosen',
  };
}

// --- Voting submit ---------------------------------------------------------

Widget buildVotingStatusCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final step = wbStateKnob<VotingStatusStepCase>(
    context,
    label: 'Step',
    options: VotingStatusStepCase.values,
    labelBuilder: votingStatusStepLabel,
  );
  final account = wbStateKnob<VotingStatusAccountCase>(
    context,
    label: 'Account',
    options: VotingStatusAccountCase.values,
    labelBuilder: votingStatusAccountLabel,
  );
  final problem = wbStateKnob<VotingStatusProblemCase>(
    context,
    label: 'Problem',
    options: VotingStatusProblemCase.values,
    labelBuilder: votingStatusProblemLabel,
  );
  final voteProgress = wbStateKnob<VotingStatusVoteProgressCase>(
    context,
    label: 'Vote progress',
    options: VotingStatusVoteProgressCase.values,
    labelBuilder: votingStatusVoteProgressLabel,
  );
  return votingStatusFixture(
    layout: layout,
    step: step,
    account: account,
    problem: problem,
    voteProgress: voteProgress,
  );
}

String votingStatusStepLabel(VotingStatusStepCase step) {
  return switch (step) {
    VotingStatusStepCase.waitingForWalletSync => 'Waiting for wallet sync',
    VotingStatusStepCase.preparing => 'Preparing',
    VotingStatusStepCase.delegating => 'Delegating',
    VotingStatusStepCase.castingVotes => 'Casting votes',
    VotingStatusStepCase.submittingShares => 'Submitting shares',
    VotingStatusStepCase.finalizing => 'Finalizing',
    VotingStatusStepCase.complete => 'Submission complete',
  };
}

String votingStatusAccountLabel(VotingStatusAccountCase account) {
  return switch (account) {
    VotingStatusAccountCase.software => 'Software',
    VotingStatusAccountCase.keystone => 'Keystone',
  };
}

String votingStatusProblemLabel(VotingStatusProblemCase problem) {
  return switch (problem) {
    VotingStatusProblemCase.none => 'None',
    VotingStatusProblemCase.couldNotStart => "Couldn't start",
    VotingStatusProblemCase.jobFailed => 'Voting failed (Retry)',
    VotingStatusProblemCase.jobFailedClearable => 'Voting failed (Clear)',
    VotingStatusProblemCase.softwareAccountRequired =>
      'Software account required',
    VotingStatusProblemCase.pirDataBehind => 'Vote data not ready',
    VotingStatusProblemCase.pirDataAhead => 'Vote data ahead of snapshot',
    VotingStatusProblemCase.pirUnreachable => 'Vote data unreachable',
    VotingStatusProblemCase.pirNoMatch => 'No matching vote data',
  };
}

String votingStatusVoteProgressLabel(VotingStatusVoteProgressCase progress) {
  return switch (progress) {
    VotingStatusVoteProgressCase.questionCount => 'Question count',
    VotingStatusVoteProgressCase.indeterminate => 'Indeterminate',
  };
}

/// Both form factors of the Keystone voting handoff behind one `Layout` knob.
/// Each lane's builder registers its own axes, so the panel's QR knob and the
/// mobile screen's Stage knob only appear in the lane that has them.
Widget buildVotingKeystoneSigningGalleryCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return layout == WbLayout.desktop
      ? buildVotingDesktopKeystoneSigningCase(context)
      : buildVotingKeystoneSigningCase(context);
}

Widget buildVotingDesktopKeystoneSigningCase(BuildContext context) {
  final qr = wbStateKnob<VotingKeystoneQrCase>(
    context,
    label: 'QR',
    options: VotingKeystoneQrCase.values,
    labelBuilder: votingKeystoneQrLabel,
  );
  final bundles = wbStateKnob<VotingKeystoneBundlesCase>(
    context,
    label: 'Bundles',
    options: VotingKeystoneBundlesCase.values,
    labelBuilder: votingKeystoneBundlesLabel,
  );
  final memos = wbStateKnob<VotingKeystoneMemosCase>(
    context,
    label: 'Memos',
    options: VotingKeystoneMemosCase.values,
    labelBuilder: votingKeystoneMemosLabel,
  );
  final scanError = wbBoolKnob(context, label: 'Scan error');
  final skipAction = wbBoolKnob(context, label: 'Skip action');
  // The desktop shell this panel sits in overflows under mobile tokens, so the
  // mobile lane gets the notice instead of a wrong render.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: votingKeystoneSigningPanelFixture(
      qr: qr,
      bundles: bundles,
      memos: memos,
      scanError: scanError,
      skipAction: skipAction,
    ),
  );
}

String votingKeystoneQrLabel(VotingKeystoneQrCase qr) {
  return switch (qr) {
    VotingKeystoneQrCase.preparing => 'Preparing',
    VotingKeystoneQrCase.ready => 'Ready',
    VotingKeystoneQrCase.failed => 'Failed',
  };
}

String votingKeystoneBundlesLabel(VotingKeystoneBundlesCase bundles) {
  return switch (bundles) {
    VotingKeystoneBundlesCase.single => '1 bundle',
    VotingKeystoneBundlesCase.batch => '2 of 3 bundles',
  };
}

String votingKeystoneMemosLabel(VotingKeystoneMemosCase memos) {
  return switch (memos) {
    VotingKeystoneMemosCase.none => 'None',
    VotingKeystoneMemosCase.one => 'One',
    // Counts, not the pager widget's name: the option is simply two memos.
    VotingKeystoneMemosCase.pager => 'Two',
  };
}

Widget buildVotingSubmitProgressCase(BuildContext context) {
  final step = wbStateKnob<VotingSubmissionProgressStep>(
    context,
    label: 'Step',
    options: VotingSubmissionProgressStep.values,
    labelBuilder: votingSubmitStepLabel,
  );
  final viewport = wbStateKnob<VotingSubmissionViewport>(
    context,
    label: 'Viewport',
    options: VotingSubmissionViewport.values,
    labelBuilder: votingSubmitViewportLabel,
  );
  final progress = wbStateKnob<VotingSubmissionProgressCase>(
    context,
    label: 'Progress',
    options: VotingSubmissionProgressCase.values,
    // Passing the step's own fraction through keeps the default render the one
    // production shows for every Step — finalizing included, which is
    // indeterminate there.
    initial: VotingSubmissionProgressCase.stepDefault,
    labelBuilder: votingSubmitProgressLabel,
  );
  return votingSubmissionProgressFixture(
    context,
    step: step,
    viewport: viewport,
    progress: progress,
  );
}

String votingSubmitProgressLabel(VotingSubmissionProgressCase progress) {
  return switch (progress) {
    VotingSubmissionProgressCase.stepDefault => 'Step default',
    VotingSubmissionProgressCase.justStarted => 'Just started',
    VotingSubmissionProgressCase.quarter => 'A quarter done',
    VotingSubmissionProgressCase.mostOfTheWay => 'Most of the way',
    VotingSubmissionProgressCase.stepComplete => 'Step complete',
    VotingSubmissionProgressCase.unknown => 'Unknown',
  };
}

String votingSubmitStepLabel(VotingSubmissionProgressStep step) {
  return switch (step) {
    VotingSubmissionProgressStep.provingAuthority => 'Proving authority',
    VotingSubmissionProgressStep.castingVotes => 'Casting votes',
    VotingSubmissionProgressStep.finalizing => 'Finalizing',
  };
}

String votingSubmitViewportLabel(VotingSubmissionViewport viewport) {
  return switch (viewport) {
    VotingSubmissionViewport.phone => 'Phone 393×852',
    VotingSubmissionViewport.compact => 'Compact 375×667',
  };
}

/// Which step of the Keystone voting handoff the screen opens on.
///
/// This is the mobile handoff. The desktop `KeystoneVotingScanScreen` owns a
/// live camera preview, so it is registered under `Screens > Scanning`, where
/// it renders against the camera fake.
enum VotingKeystoneStage { request, scanner }

Widget buildVotingKeystoneSigningCase(BuildContext context) {
  final stage = wbStateKnob<VotingKeystoneStage>(
    context,
    label: 'Stage',
    options: VotingKeystoneStage.values,
    labelBuilder: votingKeystoneStageLabel,
  );
  final bundles = wbStateKnob<VotingMobileKeystoneBundles>(
    context,
    label: 'Bundles',
    options: VotingMobileKeystoneBundles.values,
    initial: VotingMobileKeystoneBundles.batch,
    labelBuilder: votingMobileKeystoneBundlesLabel,
  );
  final memos = wbStateKnob<VotingMobileKeystoneMemos>(
    context,
    label: 'Memos',
    options: VotingMobileKeystoneMemos.values,
    initial: VotingMobileKeystoneMemos.pager,
    labelBuilder: votingMobileKeystoneMemosLabel,
  );
  final skip = wbBoolKnob(context, label: 'Skip action', initial: true);
  return votingMobileKeystoneSigningFixture(
    startInScanner: stage == VotingKeystoneStage.scanner,
    bundles: bundles,
    memos: memos,
    canSkip: skip,
  );
}

String votingKeystoneStageLabel(VotingKeystoneStage stage) {
  return switch (stage) {
    VotingKeystoneStage.request => 'Signature QR',
    VotingKeystoneStage.scanner => 'Scanner',
  };
}

String votingMobileKeystoneBundlesLabel(VotingMobileKeystoneBundles bundles) {
  return switch (bundles) {
    VotingMobileKeystoneBundles.single => '1 bundle',
    VotingMobileKeystoneBundles.batch => '2 of 3 bundles',
    VotingMobileKeystoneBundles.uncounted => 'No bundle count',
  };
}

String votingMobileKeystoneMemosLabel(VotingMobileKeystoneMemos memos) {
  return switch (memos) {
    VotingMobileKeystoneMemos.none => 'None',
    VotingMobileKeystoneMemos.one => 'One',
    VotingMobileKeystoneMemos.pager => 'Two',
  };
}

// --- Voting confirmation ---------------------------------------------------

Widget buildVotingConfirmationCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final session = wbStateKnob<VotingConfirmationSessionCase>(
    context,
    label: 'Session',
    options: VotingConfirmationSessionCase.values,
    labelBuilder: votingConfirmationSessionLabel,
  );
  final outcome = wbStateKnob<VotingConfirmationOutcomeCase>(
    context,
    label: 'Outcome',
    options: VotingConfirmationOutcomeCase.values,
    labelBuilder: votingConfirmationOutcomeLabel,
  );
  return votingConfirmationFixture(
    layout: layout,
    session: session,
    outcome: outcome,
  );
}

String votingConfirmationSessionLabel(VotingConfirmationSessionCase session) {
  return switch (session) {
    VotingConfirmationSessionCase.loaded => 'Loaded',
    VotingConfirmationSessionCase.loading => 'Loading',
    VotingConfirmationSessionCase.failedWithReceipt =>
      'Failed with cached receipt',
    VotingConfirmationSessionCase.failedWithoutReceipt =>
      'Failed with no receipt',
  };
}

String votingConfirmationOutcomeLabel(VotingConfirmationOutcomeCase outcome) {
  return switch (outcome) {
    VotingConfirmationOutcomeCase.confirmed => 'Submission confirmed',
    VotingConfirmationOutcomeCase.notComplete => 'Submission not complete',
    VotingConfirmationOutcomeCase.checkingEligibility => 'Checking eligibility',
    VotingConfirmationOutcomeCase.eligibilityNotConfirmed =>
      'Eligibility not confirmed',
    VotingConfirmationOutcomeCase.refreshFailed => 'Refresh failed (Retry)',
  };
}

// --- Voting guards ---------------------------------------------------------

Widget buildVotingAccountGuardCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final account = wbStateKnob<VotingGuardAccountCase>(
    context,
    label: 'Account',
    options: VotingGuardAccountCase.values,
    labelBuilder: votingGuardAccountLabel,
  );
  return votingAccountGuardFixture(layout: layout, account: account);
}

String votingGuardAccountLabel(VotingGuardAccountCase account) {
  return switch (account) {
    VotingGuardAccountCase.loading => 'Loading',
    VotingGuardAccountCase.failed => 'Failed to load',
  };
}

// --- Voting results --------------------------------------------------------

Widget buildVotingResultsCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final tally = wbStateKnob<VotingResultsTallyCase>(
    context,
    label: 'Tally',
    options: VotingResultsTallyCase.values,
    labelBuilder: votingResultsTallyLabel,
  );
  final voted = wbStateKnob<VotingResultsVotedCase>(
    context,
    label: 'Your vote',
    options: VotingResultsVotedCase.values,
    labelBuilder: votingResultsVotedLabel,
  );
  final proposals = wbStateKnob<VotingResultsProposalsCase>(
    context,
    label: 'Proposals',
    options: VotingResultsProposalsCase.values,
    labelBuilder: votingResultsProposalsLabel,
  );
  // `VotingResultsContent` and its cards pick their layout from
  // `kAppFormFactor`, so the knob only swaps the shell.
  return WbLaneOnly(
    layout: layout,
    child: votingResultsScreenFixture(
      layout: layout,
      tally: tally,
      voted: voted,
      proposals: proposals,
    ),
  );
}

String votingResultsTallyLabel(VotingResultsTallyCase tally) {
  return switch (tally) {
    VotingResultsTallyCase.results => 'Results',
    VotingResultsTallyCase.loading => 'Loading',
    VotingResultsTallyCase.pending => 'Results pending',
    VotingResultsTallyCase.failed => "Couldn't load results",
  };
}

String votingResultsVotedLabel(VotingResultsVotedCase voted) {
  return switch (voted) {
    VotingResultsVotedCase.voted => 'Voted',
    VotingResultsVotedCase.notVoted => 'Did not vote',
  };
}

String votingResultsProposalsLabel(VotingResultsProposalsCase proposals) {
  return switch (proposals) {
    VotingResultsProposalsCase.some => 'Some',
    VotingResultsProposalsCase.none => 'None',
  };
}

// --- Voting modals ---------------------------------------------------------

Widget buildVotingSettingsSheetCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final sources = wbStateKnob<VotingConfigSourcesCase>(
    context,
    label: 'Sources',
    options: VotingConfigSourcesCase.values,
    // The saved-source list is the state the other axes read against.
    initial: VotingConfigSourcesCase.savedSource,
    labelBuilder: votingConfigSourcesLabel,
  );
  final config = wbStateKnob<VotingConfigLoadCase>(
    context,
    label: 'Config',
    options: VotingConfigLoadCase.values,
    labelBuilder: votingConfigLoadLabel,
  );
  final testRounds = wbBoolKnob(context, label: 'Test rounds');
  final editor = wbStateKnob<VotingConfigEditorCase>(
    context,
    label: 'Editor',
    options: VotingConfigEditorCase.values,
    labelBuilder: votingConfigEditorLabel,
  );
  return votingConfigSettingsFixture(
    layout: layout,
    sources: sources,
    config: config,
    testRounds: testRounds,
    editor: editor,
  );
}

String votingConfigEditorLabel(VotingConfigEditorCase editor) {
  return switch (editor) {
    VotingConfigEditorCase.closed => 'Closed',
    VotingConfigEditorCase.addingSource => 'Adding a source',
    VotingConfigEditorCase.editingSource => 'Editing a source',
  };
}

String votingConfigSourcesLabel(VotingConfigSourcesCase sources) {
  return switch (sources) {
    VotingConfigSourcesCase.defaultOnly => 'Default only',
    VotingConfigSourcesCase.savedSource => 'Saved source added',
    VotingConfigSourcesCase.customSelected => 'Custom selected',
  };
}

String votingConfigLoadLabel(VotingConfigLoadCase config) {
  return switch (config) {
    VotingConfigLoadCase.loaded => 'Loaded',
    VotingConfigLoadCase.loading => 'Loading',
    VotingConfigLoadCase.failed => "Couldn't load",
  };
}

Widget buildVotingIneligibleDialogCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final guidance = wbBoolKnob(context, label: 'Guidance line', initial: true);
  // The dialog picks its desktop or mobile body from `kAppFormFactor`.
  return WbLaneOnly(
    layout: layout,
    child: votingIneligibleDialogFixture(layout: layout, guidance: guidance),
  );
}

Widget buildVotingSkippedQuestionsDialogCase(BuildContext context) {
  final skipped = wbStateKnob<VotingSkippedQuestionsCase>(
    context,
    label: 'Unanswered',
    options: VotingSkippedQuestionsCase.values,
    initial: VotingSkippedQuestionsCase.some,
    labelBuilder: votingSkippedQuestionsLabel,
  );
  // No layout knob: the dialog has no form-factor branch, and its 312px
  // buttons measurably overflow under mobile tokens (a production bug), so
  // the preview is pinned to the lane where the render is truthful.
  return WbLaneOnly(
    layout: WbLayout.desktop,
    child: votingSkippedQuestionsDialogFixture(
      layout: WbLayout.desktop,
      skipped: skipped,
    ),
  );
}

String votingSkippedQuestionsLabel(VotingSkippedQuestionsCase skipped) {
  return switch (skipped) {
    VotingSkippedQuestionsCase.one => 'One question',
    VotingSkippedQuestionsCase.some => 'A few questions',
    VotingSkippedQuestionsCase.all => 'Every question',
  };
}

Widget buildVotingSkipSignedBundlesDialogCase(BuildContext context) {
  // The dialog has no props; the layout knob only changes the frame it sits
  // in, which is what decides how wide it can be.
  final layout = wbLayoutKnob(context);
  return votingSkipSignedBundlesDialogFixture(layout: layout);
}

// --- Voting cards ----------------------------------------------------------

Widget buildVotingProposalCardCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final mode = wbStateKnob<VotingProposalCardModeCase>(
    context,
    label: 'Mode',
    options: VotingProposalCardModeCase.values,
    labelBuilder: votingProposalCardModeLabel,
  );
  final choice = wbStateKnob<VotingProposalCardChoiceCase>(
    context,
    label: 'Selection',
    options: VotingProposalCardChoiceCase.values,
    labelBuilder: votingProposalCardChoiceLabel,
  );
  final tone = wbStateKnob<VotingProposalCardToneCase>(
    context,
    label: 'Tone',
    options: VotingProposalCardToneCase.values,
    initial: VotingProposalCardToneCase.multipleChoice,
    labelBuilder: votingProposalCardToneLabel,
  );
  // Only the desktop card reads `titleCollapsedMaxLines`, so the knob is not
  // offered in the lane where it would do nothing.
  final title = wbCompiledLaneLayout == WbLayout.desktop
      ? wbStateKnob<VotingProposalCardTitleCase>(
          context,
          label: 'Title',
          options: VotingProposalCardTitleCase.values,
          labelBuilder: votingProposalCardTitleLabel,
        )
      : VotingProposalCardTitleCase.plain;
  final metadata = wbStateKnob<VotingProposalCardMetadataCase>(
    context,
    label: 'Metadata',
    options: VotingProposalCardMetadataCase.values,
    initial: VotingProposalCardMetadataCase.badgesAndForum,
    labelBuilder: votingProposalCardMetadataLabel,
  );
  final skipped = wbBoolKnob(context, label: 'Skipped status');
  // `VotingProposalCard` picks its desktop or mobile card from
  // `kAppFormFactor`, so the knob cannot change what renders.
  return WbLaneOnly(
    layout: layout,
    child: votingProposalCardFixture(
      layout: layout,
      mode: mode,
      choice: choice,
      tone: tone,
      title: title,
      metadata: metadata,
      skippedStatus: skipped,
    ),
  );
}

String votingProposalCardModeLabel(VotingProposalCardModeCase mode) {
  return switch (mode) {
    VotingProposalCardModeCase.interactive => 'Interactive',
    VotingProposalCardModeCase.readOnly => 'Read-only',
    VotingProposalCardModeCase.disabled => 'Not eligible',
  };
}

String votingProposalCardChoiceLabel(VotingProposalCardChoiceCase choice) {
  return switch (choice) {
    VotingProposalCardChoiceCase.none => 'No choice',
    VotingProposalCardChoiceCase.firstOption => 'First option',
    VotingProposalCardChoiceCase.missingOption => 'Missing option',
  };
}

String votingProposalCardToneLabel(VotingProposalCardToneCase tone) {
  return switch (tone) {
    VotingProposalCardToneCase.yes => 'Yes',
    VotingProposalCardToneCase.no => 'No',
    VotingProposalCardToneCase.multipleChoice => 'Multiple choice',
    VotingProposalCardToneCase.skipped => 'Skipped',
  };
}

String votingProposalCardTitleLabel(VotingProposalCardTitleCase title) {
  return switch (title) {
    VotingProposalCardTitleCase.plain => 'Plain',
    VotingProposalCardTitleCase.collapsible => 'Collapsible',
  };
}

String votingProposalCardMetadataLabel(VotingProposalCardMetadataCase value) {
  return switch (value) {
    VotingProposalCardMetadataCase.none => 'None',
    VotingProposalCardMetadataCase.oneBadge => 'One badge',
    VotingProposalCardMetadataCase.badgesAndForum => 'Two badges and forum',
  };
}

Widget buildVotingResultCardCase(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final winner = wbStateKnob<VotingResultWinnerCase>(
    context,
    label: 'Winner',
    options: VotingResultWinnerCase.values,
    labelBuilder: votingResultWinnerLabel,
  );
  final vote = wbStateKnob<VotingResultVoteCase>(
    context,
    label: 'Your vote',
    options: VotingResultVoteCase.values,
    labelBuilder: votingResultVoteLabel,
  );
  final share = wbStateKnob<VotingResultShareCase>(
    context,
    label: 'Share',
    options: VotingResultShareCase.values,
    initial: VotingResultShareCase.small,
    labelBuilder: votingResultShareLabel,
  );
  // Only the mobile row reads `profilePictureId`, so the knob is not offered
  // in the lane where it would do nothing.
  final avatar = wbCompiledLaneLayout == WbLayout.mobile
      ? wbBoolKnob(context, label: 'Avatar', initial: true)
      : true;
  final metadata = wbBoolKnob(context, label: 'Metadata', initial: true);
  // `VotingResultCard` picks its desktop or mobile body from `kAppFormFactor`.
  return WbLaneOnly(
    layout: layout,
    child: votingResultCardFixture(
      layout: layout,
      winner: winner,
      vote: vote,
      share: share,
      avatar: avatar,
      metadata: metadata,
    ),
  );
}

String votingResultWinnerLabel(VotingResultWinnerCase winner) {
  return switch (winner) {
    VotingResultWinnerCase.single => 'Single',
    VotingResultWinnerCase.tie => 'Tie',
    VotingResultWinnerCase.none => 'No votes',
  };
}

String votingResultVoteLabel(VotingResultVoteCase vote) {
  return switch (vote) {
    VotingResultVoteCase.winning => 'Winning option',
    VotingResultVoteCase.other => 'Other option',
    VotingResultVoteCase.none => 'Did not vote',
  };
}

String votingResultShareLabel(VotingResultShareCase share) {
  return switch (share) {
    VotingResultShareCase.majority => 'Majority',
    VotingResultShareCase.small => 'Small',
    VotingResultShareCase.tiny => 'Under 0.1%',
    VotingResultShareCase.zero => 'Zero',
  };
}

// --- Voting expandable text ------------------------------------------------

Widget buildVotingExpandableTextCase(BuildContext context) {
  final text = wbStateKnob<VotingExpandableTextCase>(
    context,
    label: 'Text',
    options: VotingExpandableTextCase.values,
    // Only text that overflows shows the toggle the other axes describe.
    initial: VotingExpandableTextCase.long,
    labelBuilder: votingExpandableTextLabel,
  );
  final controls = wbStateKnob<VotingExpandableControlsCase>(
    context,
    label: 'Controls',
    options: VotingExpandableControlsCase.values,
    labelBuilder: votingExpandableControlsLabel,
  );
  final toggleWhenItFits = wbBoolKnob(context, label: 'Toggle when text fits');
  return votingExpandableTextFixture(
    context,
    text: text,
    controls: controls,
    toggleWhenItFits: toggleWhenItFits,
  );
}

String votingExpandableTextLabel(VotingExpandableTextCase text) {
  return switch (text) {
    VotingExpandableTextCase.short => 'Short',
    VotingExpandableTextCase.long => 'Long',
    VotingExpandableTextCase.empty => 'Empty',
  };
}

String votingExpandableControlsLabel(VotingExpandableControlsCase controls) {
  return switch (controls) {
    VotingExpandableControlsCase.viewMore => 'View more',
    VotingExpandableControlsCase.showDescription => 'Show description',
  };
}

// --- Voting pane -----------------------------------------------------------

Widget buildVotingPanePrimitiveCase(BuildContext context) {
  final primitive = wbStateKnob<VotingPanePrimitiveCase>(
    context,
    label: 'Widget',
    options: VotingPanePrimitiveCase.values,
    labelBuilder: votingPanePrimitiveLabel,
  );
  // `backLinkMinWidth` has no knob: 60 is under the natural width of the
  // toolbar's 'Home' back link, so it changes nothing on screen.
  return votingPanePrimitiveFixture(context, primitive: primitive);
}

String votingPanePrimitiveLabel(VotingPanePrimitiveCase primitive) {
  return switch (primitive) {
    VotingPanePrimitiveCase.loading => 'Loading',
    VotingPanePrimitiveCase.stateView => 'State view',
    VotingPanePrimitiveCase.listView => 'List view',
    VotingPanePrimitiveCase.scrollView => 'Scroll view',
    VotingPanePrimitiveCase.centeredScrollView => 'Centered scroll view',
  };
}

// --- Voting scaffold -------------------------------------------------------

Widget buildVotingMobileScaffoldCase(BuildContext context) {
  final title = wbStateKnob<VotingScaffoldTitleCase>(
    context,
    label: 'Title',
    options: VotingScaffoldTitleCase.values,
    labelBuilder: votingScaffoldTitleLabel,
  );
  final padding = wbBoolKnob(context, label: 'Horizontal padding');
  // Mobile-only widget class: the desktop lane would render it with desktop
  // nav metrics.
  return WbLaneOnly(
    layout: WbLayout.mobile,
    child: votingMobileScaffoldFixture(
      context,
      title: title,
      horizontalPadding: padding,
    ),
  );
}

String votingScaffoldTitleLabel(VotingScaffoldTitleCase title) {
  return switch (title) {
    VotingScaffoldTitleCase.polls => 'Coinholder voting',
    VotingScaffoldTitleCase.voted => 'Voted',
    VotingScaffoldTitleCase.review => 'Review your answers',
    VotingScaffoldTitleCase.submit => 'Submit vote',
    VotingScaffoldTitleCase.submitted => 'Vote submitted',
    VotingScaffoldTitleCase.results => 'Voting results',
  };
}
