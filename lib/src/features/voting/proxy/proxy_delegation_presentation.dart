/// Pure mappings from the client API's state to what the delegator screens
/// show. Screens hold no rules of their own; tests drive these directly.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/l10n/l10n.dart' show AppLocalizations;
import '../voting_message.dart';
import '../voting_flow_models.dart';
import '../voting_formatters.dart';
import '../voting_progress_presentation.dart';
import 'proxy_delegation_copy.dart';
import 'proxy_delegation_repository.dart';

/// What the round screen's delegation line shows.
enum ProxyEntryKind {
  /// No card: the round is not a proxy round for this wallet.
  hidden,
  available,
  paused,
  alreadyVoted,
  usedElsewhere,
  timingUnavailable,
  voteEnded,

  /// The trust anchor no longer verifies.
  cannotVerify,

  /// The round's one allocation is committed.
  locked,
}

/// Maps a round's committed allocation and availability to the round
/// screen's delegation line.
///
/// A committed allocation always shows, whatever availability says, because
/// gates only control new allocations (LIV-12).
ProxyEntryKind proxyEntryKindFor({
  required ApiProxyAllocationStatus? status,
  required ApiProxyAvailability availability,
}) {
  if (status != null) return ProxyEntryKind.locked;
  return switch (availability.kind) {
    ApiProxyAvailabilityKind.available => ProxyEntryKind.available,
    ApiProxyAvailabilityKind.unsupported => ProxyEntryKind.hidden,
    ApiProxyAvailabilityKind.paused => ProxyEntryKind.paused,
    ApiProxyAvailabilityKind.alreadyVoted =>
      availability.usedElsewhere
          ? ProxyEntryKind.usedElsewhere
          : ProxyEntryKind.alreadyVoted,
    ApiProxyAvailabilityKind.timingUnavailable =>
      ProxyEntryKind.timingUnavailable,
    ApiProxyAvailabilityKind.voteEnded => ProxyEntryKind.voteEnded,
  };
}

/// Why [availability] blocks a new allocation, or null when it does not.
/// The confirm step re-checks availability immediately before commit.
String? proxyAvailabilityBlockCopy(
  AppLocalizations l10n,
  ApiProxyAvailability availability,
) => switch (availability.kind) {
  ApiProxyAvailabilityKind.available => null,
  ApiProxyAvailabilityKind.unsupported => l10n.proxyUnsupported,
  ApiProxyAvailabilityKind.paused => l10n.proxyPaused,
  ApiProxyAvailabilityKind.alreadyVoted =>
    availability.usedElsewhere
        ? l10n.proxyUsedElsewhere
        : l10n.proxyAlreadyVoted,
  ApiProxyAvailabilityKind.timingUnavailable => l10n.proxyTimingUnavailable,
  ApiProxyAvailabilityKind.voteEnded => l10n.proxyTooLate,
};

/// Copy for a failure from the repository; [fallback] covers unknown ones,
/// [AppLocalizations.proxyLoadError] when null.
String proxyErrorCopy(AppLocalizations l10n, Object error, {String? fallback}) {
  if (error is ProxyReviewChangedException) return l10n.proxyReviewChanged;
  if (error is! ProxyDelegationError) return fallback ?? l10n.proxyLoadError;
  return switch (error.kind) {
    ProxyDelegationErrorKind.cannotVerify => l10n.proxyCannotVerify,
    ProxyDelegationErrorKind.voteEnded => l10n.proxyTooLate,
    ProxyDelegationErrorKind.notEnoughVotingPower =>
      l10n.proxyNotEnoughVotingPower,
    ProxyDelegationErrorKind.planChanged => l10n.proxyPlanChanged,
    ProxyDelegationErrorKind.alreadyVoted => l10n.proxyAlreadyStartedVoting,
    ProxyDelegationErrorKind.registrationUnusable =>
      l10n.proxyRegistrationUnusable,
    ProxyDelegationErrorKind.keptShareUnanswered =>
      l10n.proxyKeptShareUnanswered,
    ProxyDelegationErrorKind.other => fallback ?? l10n.proxyLoadError,
  };
}

/// The delegation window the review's timing notice shows.
enum ProxyDelegationWindow {
  open,

  /// Within 24 hours of `vote_end`: delegates may not have time to vote.
  closingSoon,

  /// `tooLate`, the round-closed state votes use: `now >= vote_end`.
  closed,
}

/// How long before `vote_end` the closing-soon notice shows.
const kProxyClosingSoonWindow = Duration(hours: 24);

/// The delegation window at [now]. There is no earlier cut-off than `vote_end`.
ProxyDelegationWindow proxyDelegationWindowAt({
  required DateTime now,
  required DateTime voteEnd,
}) {
  if (!now.isBefore(voteEnd)) return ProxyDelegationWindow.closed;
  if (voteEnd.difference(now) <= kProxyClosingSoonWindow) {
    return ProxyDelegationWindow.closingSoon;
  }
  return ProxyDelegationWindow.open;
}

/// The time left before [voteEnd]: whole hours from one hour up, otherwise
/// whole minutes (at least 1). Both round down, so the notice never promises
/// more time than is left.
String proxyTimeLeftCopy(
  AppLocalizations l10n, {
  required DateTime now,
  required DateTime voteEnd,
}) {
  final left = voteEnd.difference(now);
  if (left.inHours >= 1) return l10n.proxyTimeLeftHours(left.inHours);
  return l10n.proxyTimeLeftMinutes(math.max(1, left.inMinutes));
}

/// The vote end time as the timing notice prints it.
String formatProxyVoteEnd(AppLocalizations l10n, DateTime voteEnd) =>
    formatDayMonthTime(voteEnd, l10n.localeName);

/// The step a running delegation is on.
enum ProxyProgressStep { preparing, submitting, handingOff }

/// What a delegation's progress snapshot means.
sealed class ProxyProgressOutcome {
  const ProxyProgressOutcome();
}

/// The job is still working on [step].
final class ProxyProgressRunning extends ProxyProgressOutcome {
  /// Creates the outcome.
  const ProxyProgressRunning(this.step);

  /// Current step.
  final ProxyProgressStep step;
}

/// Every delegation is handed off (and, when planned immediate, share 0's
/// reveal is confirmed).
final class ProxyProgressComplete extends ProxyProgressOutcome {
  /// Creates the outcome.
  const ProxyProgressComplete();
}

/// `vote_end` passed first; the job fails as an unconfirmed immediate vote
/// share does, with the same message.
final class ProxyProgressExpired extends ProxyProgressOutcome {
  /// Creates the outcome.
  const ProxyProgressExpired();

  /// The vote path's expired-share message.
  VotingMessage get message =>
      const VotingNotice(VotingNoticeKind.immediateShareExpired);
}

/// The chain refused a sent batch; the job keeps sending it until it lands
/// or voting ends.
final class ProxyProgressRefused extends ProxyProgressOutcome {
  /// Creates the outcome.
  const ProxyProgressRefused();
}

/// After the tally transition, a delegation was never handed off.
final class ProxyProgressNotCounted extends ProxyProgressOutcome {
  /// Creates the outcome.
  const ProxyProgressNotCounted();
}

/// Maps a progress snapshot to its outcome, in precedence order: complete,
/// not counted, expired at `vote_end`, refused by the chain, running.
ProxyProgressOutcome proxyProgressOutcome(
  ApiProxyDelegationProgress progress, {
  required DateTime now,
  required DateTime voteEnd,
}) {
  final delegations = progress.delegations;
  final handedOff =
      delegations.isNotEmpty &&
      delegations.every((view) => view.stage == ProxyDelegationStage.handedOff);
  if (handedOff &&
      (!progress.plannedImmediate || progress.immediateRevealConfirmed)) {
    return const ProxyProgressComplete();
  }
  if (delegations.any(
    (view) => view.stage == ProxyDelegationStage.notCounted,
  )) {
    return const ProxyProgressNotCounted();
  }
  if (!now.isBefore(voteEnd)) return const ProxyProgressExpired();
  if (progress.refusedByChain) return const ProxyProgressRefused();
  return ProxyProgressRunning(_progressStep(delegations));
}

/// The earliest step any delegation is on.
ProxyProgressStep _progressStep(List<ApiProxyDelegationView> delegations) {
  var step = ProxyProgressStep.handingOff;
  for (final view in delegations) {
    final viewStep = switch (view.stage) {
      ProxyDelegationStage.preparing => ProxyProgressStep.preparing,
      ProxyDelegationStage.submitting => ProxyProgressStep.submitting,
      _ => ProxyProgressStep.handingOff,
    };
    if (viewStep.index < step.index) step = viewStep;
  }
  return step;
}

/// The round status's stage word for [stage].
String proxyStageLabel(AppLocalizations l10n, ProxyDelegationStage stage) =>
    switch (stage) {
      ProxyDelegationStage.preparing => l10n.commonPreparing,
      ProxyDelegationStage.submitting => l10n.proxyStageSubmitting,
      ProxyDelegationStage.included => l10n.proxyStageIncluded,
      ProxyDelegationStage.handedOff => l10n.proxyHandedOffLabel,
      ProxyDelegationStage.notCounted => l10n.proxyNotCountedLabel,
    };

/// The round status's summary line for one delegation.
String proxyDelegationLine(
  AppLocalizations l10n,
  ApiProxyDelegationView view,
) => l10n.proxyDelegatedLine(
  formatProxyBallots(view.ballots),
  proxyViewName(view),
  proxyStageLabel(l10n, view.stage),
);

/// How a committed delegation names its delegate in a sentence.
String proxyViewName(ApiProxyDelegationView view) =>
    proxyDelegateName(view.handle);

/// How a listing names its delegate in a sentence.
String proxyListingName(ProxyDelegateListing listing) =>
    proxyDelegateName(listing.handle);

/// One published choice: the proposal and the option the ballot picked.
typedef ProxyBallotChoice = ({String proposal, String option});

/// The ballot's choices labelled with [proposals]; empty without a ballot.
List<ProxyBallotChoice> proxyBallotChoices(
  AppLocalizations l10n,
  ApiDelegateBallotView ballot,
  List<VotingProposalView> proposals,
) {
  final options = switch (ballot.kind) {
    ApiDelegateBallotKind.submitted ||
    ApiDelegateBallotKind.counted => ballot.options,
    _ => const <int>[],
  };
  return [
    for (final proposal in proposals)
      if (proposal.id >= 1 && proposal.id <= options.length)
        (
          proposal: proposal.title,
          option: _optionLabel(l10n, proposal, options[proposal.id - 1]),
        ),
  ];
}

/// The label of option [index], or a numbered fallback.
String _optionLabel(
  AppLocalizations l10n,
  VotingProposalView proposal,
  int index,
) {
  for (final option in proposal.options) {
    if (option.index == index) return option.label;
  }
  return l10n.proxyOptionFallback(index + 1);
}

/// Formats ballots as ZEC, for example `12.5 ZEC`.
String formatProxyBallots(BigInt ballots) =>
    formatVotingPower(proxyBallotsToZatoshi(ballots));

/// Formats basis points as a percentage, for example `33.33%`.
String formatProxyPercent(int bps) {
  final whole = bps ~/ 100;
  final fraction = (bps % 100).toString().padLeft(2, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '$whole%' : '$whole.$trimmed%';
}

/// Parses a percentage with at most two decimals into basis points, or
/// returns null when [text] is not a number.
int? parseProxyPercent(String text) {
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{0,2}))?$').firstMatch(text.trim());
  if (match == null) return null;
  final whole = int.parse(match[1]!);
  final fraction = (match[2] ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

/// The canonical delegate display, for example `#17 · qqqs-yqcy-q5rq-wzqf`.
String formatProxyDelegateId(int index, String fingerprint) =>
    '#$index · $fingerprint';

/// The review's line for a pre-proving [check] that blocks delegating to
/// [name], from [proxyDelegateName], or null for [DelegateCheck.ok] and for
/// [DelegateCheck.cannotVerify], which the review reports once for all.
String? proxyCheckBlockCopy(
  AppLocalizations l10n,
  String name,
  DelegateCheck check,
) => switch (check) {
  DelegateCheck.ok || DelegateCheck.cannotVerify => null,
  DelegateCheck.suspended => proxyBlockedCopy(l10n, name, retired: false),
  DelegateCheck.retired => proxyBlockedCopy(l10n, name, retired: true),
  DelegateCheck.notFound => l10n.proxyNotOnChain(name),
  DelegateCheck.mismatch => l10n.proxyMismatch(name),
};

/// One chosen delegate in the round's delegation draft.
@immutable
class ProxyDraftDelegate {
  /// Creates a draft row.
  const ProxyDraftDelegate({required this.entry, this.percentBps});

  /// The delegate as it was when chosen.
  final ProxyDelegateListing entry;

  /// Share in basis points, or null until entered.
  final int? percentBps;

  /// Returns a copy with [bps].
  ProxyDraftDelegate withPercent(int? bps) =>
      ProxyDraftDelegate(entry: entry, percentBps: bps);
}

/// The PD-2 to PD-5 selection and split, before the review commits it.
@immutable
class ProxyAllocationDraft {
  /// Creates a draft.
  const ProxyAllocationDraft({this.delegates = const []});

  /// Chosen delegates in selection order, at most [kProxyMaxDelegates].
  final List<ProxyDraftDelegate> delegates;

  /// Whether the picker has stopped at [kProxyMaxDelegates].
  bool get isFull => delegates.length >= kProxyMaxDelegates;

  /// Whether [index] is chosen.
  bool contains(int index) =>
      delegates.any((delegate) => delegate.entry.index == index);

  /// Sum of entered shares.
  int get assignedBps =>
      delegates.fold(0, (sum, delegate) => sum + (delegate.percentBps ?? 0));

  /// Share kept for the wallet's own vote.
  int get keptBps => math.max(0, kProxyFullBps - assignedBps);

  /// The first problem blocking a preview, or null when the draft is valid.
  ProxyDraftIssue? get issue {
    if (delegates.isEmpty) return ProxyDraftIssue.noDelegates;
    if (delegates.any((d) => d.percentBps == null || d.percentBps! <= 0)) {
      return ProxyDraftIssue.missingPercent;
    }
    if (assignedBps > kProxyFullBps) return ProxyDraftIssue.overAllocated;
    return null;
  }

  /// The allocation request for a valid draft.
  ProxyAllocationRequest toRequest(String roundId) => ProxyAllocationRequest(
    roundId: roundId,
    choices: [
      for (final delegate in delegates)
        delegate.entry.choice(delegate.percentBps ?? 0),
    ],
  );
}

/// Why a draft cannot be previewed yet.
enum ProxyDraftIssue { noDelegates, missingPercent, overAllocated }

/// Copy for [issue].
String proxyDraftIssueCopy(AppLocalizations l10n, ProxyDraftIssue issue) =>
    switch (issue) {
      ProxyDraftIssue.noDelegates => l10n.proxyNoDelegates,
      ProxyDraftIssue.missingPercent => l10n.proxyPercentRequired,
      ProxyDraftIssue.overAllocated => l10n.proxyPercentOver,
    };

/// Even shares for [count] delegates summing to [kProxyFullBps]; earlier
/// rows take the leftover basis points.
List<int> proxyEvenSplit(int count) {
  if (count <= 0) return const [];
  final base = kProxyFullBps ~/ count;
  final extra = kProxyFullBps % count;
  return [for (var i = 0; i < count; i++) base + (i < extra ? 1 : 0)];
}

// The delegation as one way of answering the ballot (ERRATA item 10): the
// round's questions, its review, its progress and its status show it.

/// Delegate names from [proxyDelegateName] as one phrase, for example `@a`,
/// `@a and @b` or `@a, @b and @c`.
String proxyNamesPhrase(AppLocalizations l10n, List<String> names) {
  if (names.length <= 1) return names.join();
  return l10n.proxyNamesAnd(
    names.sublist(0, names.length - 1).join(', '),
    names.last,
  );
}

/// One delegate's part of the ballot, with its planned or committed weight;
/// [name] comes from [proxyDelegateName].
typedef ProxyBallotDelegate = ({int index, String name, BigInt? ballots});

/// The delegation part of a round's ballot: the draft being built on the
/// round screen, or the round's committed allocation.
@immutable
class ProxyBallotDelegation {
  /// Creates the view.
  const ProxyBallotDelegation({
    required this.delegates,
    required this.keptBallots,
    required this.everythingDelegated,
    required this.committed,
    this.issue,
  });

  /// The chosen delegates in order.
  final List<ProxyBallotDelegate> delegates;

  /// Ballots left for the wallet's own answers; null until previewed.
  final BigInt? keptBallots;

  /// Whether the delegates answer every question, so the wallet has
  /// nothing of its own to answer.
  final bool everythingDelegated;

  /// Whether this is the committed allocation rather than a draft.
  final bool committed;

  /// Why a draft cannot be submitted yet; null when it can.
  final ProxyDraftIssue? issue;

  /// The delegates' names, from [proxyDelegateName].
  List<String> get names => [for (final delegate in delegates) delegate.name];
}

/// The round's ballot delegation from its committed [status], or else from
/// the round screen's [draft] and its planner [preview]. Null when neither
/// names a delegate.
ProxyBallotDelegation? proxyBallotDelegationFor({
  required ApiProxyAllocationStatus? status,
  required ProxyAllocationDraft draft,
  required ProxyAllocationPreview? preview,
}) {
  if (status != null) {
    if (status.delegations.isEmpty) return null;
    return ProxyBallotDelegation(
      delegates: [
        for (final view in status.delegations)
          (
            index: view.delegateIndex,
            name: proxyViewName(view),
            ballots: view.ballots,
          ),
      ],
      keptBallots: status.keptBallots,
      everythingDelegated: status.keptBallots == BigInt.zero,
      committed: true,
    );
  }
  if (draft.delegates.isEmpty) return null;
  final issue = draft.issue;
  final planned = issue == null ? preview : null;
  return ProxyBallotDelegation(
    delegates: [
      for (final delegate in draft.delegates)
        (
          index: delegate.entry.index,
          name: proxyListingName(delegate.entry),
          ballots: planned?.delegations
              .where((d) => d.delegateIndex == delegate.entry.index)
              .firstOrNull
              ?.ballots,
        ),
    ],
    keptBallots: planned?.keptBallots,
    everythingDelegated:
        draft.keptBps == 0 || planned?.keptBallots == BigInt.zero,
    committed: false,
    issue: issue,
  );
}

/// The round screen's split line, for example
/// `4 ZEC to @alice · 4 ZEC for you to answer`. Amounts show once the
/// planner has previewed them.
String proxyBallotSplitText(
  AppLocalizations l10n,
  ProxyBallotDelegation delegation,
) {
  final parts = [
    for (final delegate in delegation.delegates)
      proxySplitToCopy(
        l10n,
        amount: delegate.ballots == null
            ? null
            : formatProxyBallots(delegate.ballots!),
        name: delegate.name,
      ),
  ];
  final kept = delegation.keptBallots;
  if (!delegation.everythingDelegated && kept != null && kept > BigInt.zero) {
    parts.add(l10n.proxyKeptToAnswer(formatProxyBallots(kept)));
  }
  return parts.join(' · ');
}

/// Where a delegation stands for the progress screen: zcash_voting's live
/// [progress], each delegation advanced to the furthest stage [status] has
/// seen, since the two are read at different times.
ApiProxyDelegationProgress mergedProxyProgress({
  required ApiProxyAllocationStatus status,
  ApiProxyDelegationProgress? progress,
}) {
  final byIndex = {
    for (final view
        in progress?.delegations ?? const <ApiProxyDelegationView>[])
      view.delegateIndex: view,
  };
  return ApiProxyDelegationProgress(
    delegations: [
      for (final view in status.delegations)
        _furtherView(view, byIndex[view.delegateIndex]),
    ],
    plannedImmediate: progress?.plannedImmediate ?? false,
    immediateRevealConfirmed: progress?.immediateRevealConfirmed ?? false,
    refusedByChain: progress?.refusedByChain ?? false,
  );
}

/// Whichever of [a] and [b] is further along; an end state wins.
ApiProxyDelegationView _furtherView(
  ApiProxyDelegationView a,
  ApiProxyDelegationView? b,
) {
  if (b == null) return a;
  return b.stage.index >= a.stage.index ? b : a;
}

/// One row of the progress screen when the ballot carries a delegation: the
/// vote's own rows with the delegation's added after proving.
enum ProxyBallotStep {
  /// "Proving voting authority", while the delegation is prepared.
  proving,

  /// "Delegating to @x", until the delegation lands on chain.
  delegating,

  /// "Casting votes and submitting shares", for the wallet's own answers.
  casting,

  /// "Finalizing submission", until the delegation's immediate reveal is
  /// confirmed (plan PD-6) and any casts finish, as a vote's finalizing
  /// step.
  finalizing,
}

/// The progress screen's rows for a ballot that carries a delegation, and
/// how far the submission is.
@immutable
class ProxyBallotProgress {
  /// Creates the view.
  const ProxyBallotProgress({
    required this.steps,
    required this.current,
    required this.running,
    required this.outcome,
    required this.names,
  });

  /// The rows that apply, in order.
  final List<ProxyBallotStep> steps;

  /// The row under way; [steps]' length once all are done.
  final int current;

  /// Whether the row at [current] is moving, not held by a refusal or an end.
  final bool running;

  /// What the delegation's progress means on its own.
  final ProxyProgressOutcome outcome;

  /// The delegates the delegation goes to, from [proxyDelegateName].
  final List<String> names;

  /// Whether every row is done.
  bool get complete => current >= steps.length;
}

/// The rows and position of a submission carrying [delegation].
///
/// [castsVotes] is false when the delegates took everything, or the
/// wallet answered nothing, so no casting row shows. [ballotStep] is the
/// vote job's ratcheted step, with [ballotComplete] once its casts are
/// done; both are absent for a proxy job. [jobComplete] ends every row.
ProxyBallotProgress proxyBallotProgress({
  required ApiProxyDelegationProgress delegation,
  required bool castsVotes,
  required int? ballotStep,
  required bool ballotComplete,
  required bool jobComplete,
  required DateTime now,
  required DateTime voteEnd,
}) {
  final outcome = proxyProgressOutcome(delegation, now: now, voteEnd: voteEnd);
  final names = [
    for (final view in delegation.delegations) proxyViewName(view),
  ];
  final steps = [
    ProxyBallotStep.proving,
    ProxyBallotStep.delegating,
    if (castsVotes) ProxyBallotStep.casting,
    ProxyBallotStep.finalizing,
  ];
  // The delegation's position: 0 preparing, 1 on its way, 2 landed, 3
  // handed off. A refusal holds it on its way.
  final delegated = switch (outcome) {
    ProxyProgressRunning(step: ProxyProgressStep.preparing) => 0,
    ProxyProgressRunning(step: ProxyProgressStep.submitting) => 1,
    ProxyProgressRefused() => 1,
    ProxyProgressRunning(step: ProxyProgressStep.handingOff) => 2,
    _ => 3,
  };
  // The ballot's position: 0 proving, 1 casting, 2 casts done.
  final ballot = ballotComplete ? 2 : ballotStep;
  bool done(ProxyBallotStep step) => switch (step) {
    ProxyBallotStep.proving => delegated >= 1 || (ballot ?? 0) >= 1,
    // A cast from a delegated bundle waits for its batch to land.
    ProxyBallotStep.delegating => delegated >= 2 || (ballot ?? 0) >= 1,
    ProxyBallotStep.casting => (ballot ?? 0) >= 2,
    ProxyBallotStep.finalizing =>
      jobComplete || (ballot == null && delegated >= 3),
  };
  var current = steps.length;
  for (final (i, step) in steps.indexed) {
    if (!done(step)) {
      current = i;
      break;
    }
  }
  return ProxyBallotProgress(
    steps: steps,
    current: current,
    running: switch (outcome) {
      ProxyProgressRefused() ||
      ProxyProgressExpired() ||
      ProxyProgressNotCounted() => false,
      _ => true,
    },
    outcome: outcome,
    names: names,
  );
}

/// The label of [step] for a delegation to [names]: the vote's own
/// label, or "Delegating to" the names.
String proxyBallotStepLabel(
  AppLocalizations l10n,
  ProxyBallotStep step,
  List<String> names,
) => switch (step) {
  ProxyBallotStep.proving => votingSubmissionProgressStepLabel(
    l10n,
    VotingSubmissionProgressStep.provingAuthority,
  ),
  ProxyBallotStep.delegating => l10n.proxyDelegatingStep(
    proxyNamesPhrase(l10n, names),
  ),
  ProxyBallotStep.casting => votingSubmissionProgressStepLabel(
    l10n,
    VotingSubmissionProgressStep.castingVotes,
  ),
  ProxyBallotStep.finalizing => votingSubmissionProgressStepLabel(
    l10n,
    VotingSubmissionProgressStep.finalizing,
  ),
};

/// One line of a question's status for a delegated round: whose weight it
/// is, how much, and what that weight answers.
typedef ProxyQuestionLine = ({String who, String amount, String answer});

/// The status lines of [proposal]: the wallet's own [ownChoice] with its
/// [keptBallots], then each delegate's ballot choice with its weight, or
/// that the delegate has no ballot yet. After the close a counted ballot
/// says so, and a missing one says it was not counted.
List<ProxyQuestionLine> proxyQuestionLines(
  AppLocalizations l10n, {
  required VotingProposalView proposal,
  required int? ownChoice,
  required ApiProxyAllocationStatus status,
}) {
  return [
    if (ownChoice != null && status.keptBallots > BigInt.zero)
      (
        who: l10n.proxyYouLabel,
        amount: formatProxyBallots(status.keptBallots),
        answer: _optionLabel(l10n, proposal, ownChoice),
      ),
    for (final view in status.delegations)
      (
        who: proxyViewName(view),
        amount: formatProxyBallots(view.ballots),
        answer: _delegateAnswer(l10n, proposal, view),
      ),
  ];
}

/// What delegate [view]'s ballot answers on [proposal].
String _delegateAnswer(
  AppLocalizations l10n,
  VotingProposalView proposal,
  ApiProxyDelegationView view,
) {
  if (view.stage == ProxyDelegationStage.notCounted) {
    return l10n.proxyNotCountedLabel;
  }
  final options = view.ballot.options;
  return switch (view.ballot.kind) {
    ApiDelegateBallotKind.noBallotYet => l10n.proxyHasNotVotedYet(
      proxyViewName(view),
    ),
    ApiDelegateBallotKind.notCounted => l10n.proxyNoBallotNotCountedLabel,
    ApiDelegateBallotKind.submitted => _ballotOption(l10n, proposal, options),
    ApiDelegateBallotKind.counted =>
      '${_ballotOption(l10n, proposal, options)} · ${l10n.proxyCountedLabel}',
  };
}

/// The label [options] pick on [proposal], or "no ballot yet" when the
/// ballot does not cover it.
String _ballotOption(
  AppLocalizations l10n,
  VotingProposalView proposal,
  List<int> options,
) {
  final position = proposal.id - 1;
  if (position < 0 || position >= options.length) {
    return l10n.proxyNoBallotYetLabel;
  }
  return _optionLabel(l10n, proposal, options[position]);
}
