/// Pure mappings from delegate-mode state to what the DG screens show.
/// Screens hold no rules of their own; tests drive these directly.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/formatting/date_format.dart';
import '../../../core/l10n/l10n.dart' show AppLocalizations;
import '../voting_flow_models.dart';
import 'delegate_mode_models.dart';
import 'delegate_mode_repository.dart';
import 'proxy_delegation_copy.dart';
import 'proxy_delegation_models.dart';
import 'proxy_delegation_presentation.dart';

/// What the delegate-mode home shows for a status.
enum DelegateHomeStage {
  /// No key on the device: DG-1 intro with create and import.
  intro,

  /// The key awaits its registration.
  finishRegistering,

  /// Registered: the DG-8 dashboard.
  dashboard,

  /// The key's entry is retired, so the device can start over.
  retired,
}

/// The home stage for [status].
DelegateHomeStage delegateHomeStage(DelegateModeView status) {
  if (status.key == null) return DelegateHomeStage.intro;
  if (!status.registered) return DelegateHomeStage.finishRegistering;
  if (status.retired) return DelegateHomeStage.retired;
  return DelegateHomeStage.dashboard;
}

/// Copy for a failure from the repository; [fallback] covers unknown ones,
/// [AppLocalizations.delegateLoadError] when null.
String delegateModeErrorCopy(
  AppLocalizations l10n,
  Object error, {
  String? fallback,
}) {
  final otherwise = fallback ?? l10n.delegateLoadError;
  if (error is! DelegateModeException) return otherwise;
  return switch (error.kind) {
    DelegateModeErrorKind.cannotVerify => l10n.proxyCannotVerify,
    DelegateModeErrorKind.unavailable => l10n.delegateUnavailable,
    DelegateModeErrorKind.cancelled || DelegateModeErrorKind.other => otherwise,
  };
}

/// Whether [error] is a dismissed re-auth: nothing was signed, and the
/// screen goes back to where it was without an error.
bool delegateSigningCancelled(Object error) =>
    error is DelegateModeException &&
    error.kind == DelegateModeErrorKind.cancelled;

/// The key's display form: `#17 · qqqs-yqcy-q5rq-wzqf` once the entry has
/// an index, the bare fingerprint before.
String formatDelegateKey(DelegateKeyInfo key, {int? delegateIndex}) =>
    delegateIndex == null
    ? key.fingerprint
    : formatProxyDelegateId(delegateIndex, key.fingerprint);

/// The attester error copy with its retry time formatted.
String delegateVerifierErrorText(
  AppLocalizations l10n,
  DelegateVerifierRefusal refusal,
) {
  final retryAfter = refusal.retryAfter;
  return delegateVerifierErrorCopy(
    l10n,
    refusal.error,
    retryTime: retryAfter == null
        ? null
        : formatDayMonthTime(proxyTimeFromSeconds(retryAfter), l10n.localeName),
  );
}

/// Whether a REGISTER rejection is fixed by verifying the post again: an
/// attestation the chain refused (64, 65).
bool delegateRegisterNeedsNewAttestation(DelegateRegisterRejected rejected) =>
    rejected.codespace == 'vote' && const {64, 65}.contains(rejected.code);

/// Whether [url] looks like a link to a post for [provider]: an `x.com` or
/// `twitter.com` status, or a `gist.github.com` gist. The attester still
/// decides; this only catches a pasted handle or profile link.
bool delegateProofUrlLooksRight(ProxyDelegateProvider provider, String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.scheme != 'https') return false;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return switch (provider) {
    ProxyDelegateProvider.x =>
      const {'x.com', 'twitter.com', 'mobile.x.com'}.contains(uri.host) &&
          segments.length >= 3 &&
          segments[1] == 'status' &&
          RegExp(r'^\d+$').hasMatch(segments[2]),
    ProxyDelegateProvider.gitHub =>
      uri.host == 'gist.github.com' && segments.isNotEmpty,
  };
}

/// The approximate delegation count `ceil(R / 16)` for [revealedShares]
/// R. The true count lies between this and R (plan section 5 (iv)).
BigInt delegateApproxCount(BigInt revealedShares) {
  if (revealedShares <= BigInt.zero) return BigInt.zero;
  const perDelegation = kDelegateSharesPerDelegation;
  return (revealedShares + BigInt.from(perDelegation - 1)) ~/
      BigInt.from(perDelegation);
}

/// DG-8 count line for [revealedShares].
String delegateCountText(AppLocalizations l10n, BigInt revealedShares) =>
    delegateCountCopy(l10n, delegateApproxCount(revealedShares));

/// How close the ballot deadline is (plan section 4.5, Delegate mode).
enum DelegateBallotUrgency {
  /// A ballot is on chain; nothing to remind.
  done,

  /// No ballot on chain yet: the reminder.
  reminder,

  /// The final 5 minutes: the warning.
  finalMinutes,

  /// The final 60 seconds: Submit needs a blocking confirm.
  finalSeconds,

  /// `now >= vote_end`: a ballot can no longer land.
  closed,
}

/// The final stretch that shows the warning.
const kDelegateFinalMinutesWindow = Duration(minutes: 5);

/// The final stretch that needs a blocking confirm before Submit.
const kDelegateFinalSecondsWindow = Duration(seconds: 60);

/// The urgency at [now] for a round ending at [voteEnd].
DelegateBallotUrgency delegateBallotUrgency({
  required DateTime now,
  required DateTime voteEnd,
  required bool ballotOnChain,
}) {
  if (ballotOnChain) return DelegateBallotUrgency.done;
  if (!now.isBefore(voteEnd)) return DelegateBallotUrgency.closed;
  final left = voteEnd.difference(now);
  if (left <= kDelegateFinalSecondsWindow) {
    return DelegateBallotUrgency.finalSeconds;
  }
  if (left <= kDelegateFinalMinutesWindow) {
    return DelegateBallotUrgency.finalMinutes;
  }
  return DelegateBallotUrgency.reminder;
}

/// When the urgency at [now] next changes, or null after `vote_end`. The
/// screens rebuild then, so warnings appear on time.
DateTime? delegateNextUrgencyChange({
  required DateTime now,
  required DateTime voteEnd,
}) {
  for (final boundary in [
    voteEnd.subtract(kDelegateFinalMinutesWindow),
    voteEnd.subtract(kDelegateFinalSecondsWindow),
    voteEnd,
  ]) {
    if (now.isBefore(boundary)) return boundary;
  }
  return null;
}

/// Whole minutes left before [voteEnd], rounded up and at least 1.
int delegateMinutesLeft({required DateTime now, required DateTime voteEnd}) {
  final seconds = voteEnd.difference(now).inSeconds;
  return math.max(1, (seconds / 60).ceil());
}

/// The ballot's options in proposal order, `options[i]` answering proposal
/// `i + 1`; null while any question is unanswered. There is no abstain
/// value: a question without a choice keeps the ballot incomplete.
List<int>? delegateBallotOptions(
  List<VotingProposalView> proposals,
  Map<int, int> choices,
) {
  if (proposals.isEmpty) return null;
  final ordered = [...proposals]..sort((a, b) => a.id.compareTo(b.id));
  final options = <int>[];
  for (final (i, proposal) in ordered.indexed) {
    if (proposal.id != i + 1) return null;
    final choice = choices[proposal.id];
    if (choice == null) return null;
    if (!proposal.options.any((option) => option.index == choice)) {
      return null;
    }
    options.add(choice);
  }
  return options;
}

/// Choices keyed by proposal id for [options], the inverse of
/// [delegateBallotOptions].
Map<int, int> delegateBallotChoices(List<int> options) => {
  for (final (i, option) in options.indexed) i + 1: option,
};

/// Each question with the option [options] picks, for the confirm sheet.
List<ProxyBallotChoice> delegateBallotChoiceLabels(
  AppLocalizations l10n,
  List<VotingProposalView> proposals,
  List<int> options,
) => proxyBallotChoices(
  l10n,
  ApiDelegateBallotView(
    kind: ApiDelegateBallotKind.submitted,
    options: Uint32List.fromList(options),
  ),
  [...proposals]..sort((a, b) => a.id.compareTo(b.id)),
);

/// DG-9 explanation when this device cannot sign the round's ballot, or
/// null when it can.
String? delegateBallotBlockCopy(
  AppLocalizations l10n,
  DelegateBallotBlock? block,
) => switch (block) {
  null => null,
  DelegateBallotBlock.notRegistered => l10n.delegateNotRegistered,
  DelegateBallotBlock.suspended => l10n.delegateSuspended,
  DelegateBallotBlock.retired => l10n.delegateRetiredBallot,
};

/// DG-8 ballot line for the delegate's own [ballot]. A listed ballot reads
/// as submitted until voting ends, since its weight is counted at close.
String delegateBallotStatusLabel(
  AppLocalizations l10n,
  ApiDelegateBallotView ballot,
) => switch (ballot.kind) {
  ApiDelegateBallotKind.noBallotYet => l10n.proxyNoBallotYetLabel,
  ApiDelegateBallotKind.submitted => l10n.delegateBallotSubmittedLabel,
  ApiDelegateBallotKind.counted => l10n.proxyCountedLabel,
  ApiDelegateBallotKind.notCounted => l10n.proxyNoBallotNotCountedLabel,
};

/// Whether this device submitted [round]'s ballot, the round's ballot list
/// does not show it yet, the entry is not retired and voting is open at
/// [now]. DG-8 and DG-9 then show it as confirming on chain, with no way to
/// submit it again: the app resends it in the background
/// (`DelegateBallotResender`), and keeps checking while the entry is
/// suspended.
bool delegateBallotPending(DelegateRound round, DateTime now) =>
    round.onChainOptions == null &&
    round.view.storedBallot != null &&
    round.view.ballotBlock != DelegateBallotBlock.retired &&
    now.isBefore(round.voteEndTime);
