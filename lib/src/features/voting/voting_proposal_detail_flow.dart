import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting/date_format.dart';
import '../../providers/voting/voting_session_provider.dart';
import '../../providers/voting/voting_state.dart';
import '../../providers/voting/voting_tree_sync_provider.dart';
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import 'voting_error_messages.dart';
import 'voting_flow_models.dart';
import 'voting_formatters.dart';
import 'voting_poll_ordering.dart';
import 'voting_resume_plan.dart';
import 'voting_routes.dart';

/// One renderable state of the proposal detail screen. Produced by
/// [VotingProposalDetailFlow]; rendered by the form-factor screens.
sealed class VotingProposalDetailView {
  const VotingProposalDetailView();
}

class VotingDetailLoading extends VotingProposalDetailView {
  const VotingDetailLoading();
}

class VotingDetailMessage extends VotingProposalDetailView {
  const VotingDetailMessage({required this.title, required this.message});

  final String title;
  final String message;
}

/// The round is no longer active; the flow has scheduled a redirect to the
/// results route and the screen should render a loading state until it fires.
class VotingDetailRedirecting extends VotingProposalDetailView {
  const VotingDetailRedirecting();
}

/// An unfinished vote exists for this round; the only action is resuming the
/// submission on the status route.
class VotingDetailPendingVote extends VotingProposalDetailView {
  const VotingDetailPendingVote({
    required this.roundTitle,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.roundId,
    required this.accountUuid,
  });

  final String roundTitle;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final String roundId;
  final String? accountUuid;
}

/// The account already voted; render the recorded choices read-only.
class VotingDetailVoted extends VotingProposalDetailView {
  const VotingDetailVoted({
    required this.roundTitle,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votedAt,
    required this.proposals,
    required this.choicesByProposalId,
  });

  final String roundTitle;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final DateTime? votedAt;
  final List<VotingProposalView> proposals;
  final Map<int, int?> choicesByProposalId;
}

/// The round is active and this account can pick choices.
class VotingDetailActive extends VotingProposalDetailView {
  const VotingDetailActive({
    required this.roundId,
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.endDate,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votingEligibilityConfirmed,
    required this.votingEligibilityMessage,
    required this.votingEligibilityErrorMessage,
    required this.onVotingEligibilityRetry,
    required this.proposals,
    required this.draft,
    required this.onChoice,
  });

  final String roundId;
  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final DateTime? endDate;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final bool votingEligibilityConfirmed;
  final String? votingEligibilityMessage;
  final String? votingEligibilityErrorMessage;
  final VoidCallback onVotingEligibilityRetry;
  final List<VotingProposalView> proposals;
  final VotingDraftState draft;
  final void Function(int proposalId, int? choice) onChoice;
}

typedef VotingProposalDetailBuilder =
    Widget Function(BuildContext context, VotingProposalDetailView view);

/// Shared state machine behind the proposal detail screens.
///
/// Owns voting-power preparation, the delegation PIR precompute warm-up, the
/// vote-tree pre-sync kick, and the redirect to results for inactive rounds,
/// then hands one of the [VotingProposalDetailView] states to a form-factor
/// scaffold via [builder].
class VotingProposalDetailFlow extends ConsumerStatefulWidget {
  const VotingProposalDetailFlow({
    super.key,
    required this.roundId,
    required this.builder,
  });

  final String roundId;
  final VotingProposalDetailBuilder builder;

  @override
  ConsumerState<VotingProposalDetailFlow> createState() =>
      _VotingProposalDetailFlowState();
}

class _VotingProposalDetailFlowState
    extends ConsumerState<VotingProposalDetailFlow> {
  bool _votingPowerPreparationStarted = false;
  bool _votingPowerPreparationInFlight = false;
  String? _votingPowerPreparationKey;
  String? _delegationPirPrecomputeKey;
  String? _resultsRedirectRoundId;

  @override
  void didUpdateWidget(covariant VotingProposalDetailFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId != widget.roundId) {
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
      _votingPowerPreparationKey = null;
      _delegationPirPrecomputeKey = null;
      _resultsRedirectRoundId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final roundId = widget.roundId;
    final session = ref.watch(votingSessionProvider(roundId));
    final view = session.when(
      skipLoadingOnRefresh: false,
      loading: () => const VotingDetailLoading(),
      error: (error, _) => VotingDetailMessage(
        title: "Couldn't load voting round",
        message: friendlyVotingErrorMessage(error),
      ),
      data: (state) {
        final round = state.round;
        if (round == null) {
          return const VotingDetailMessage(
            title: 'Voting round unavailable',
            message: 'The selected voting round could not be loaded.',
          );
        }
        if (shouldPreSyncVotingTree(round.status)) {
          unawaited(
            ref.read(votingTreePreSyncProvider).preSyncRound(round.roundId),
          );
        }
        final accountUuid = state.accountUuid;
        final proposals = proposalsFromRound(round);
        final forumUri = votingRoundForumUriFromJson(round.rawJson);
        final completedVote = _CompletedVote.fromPlan(state.roundPlan);
        final pendingVote = _PendingVoteRecovery.fromPlan(state.roundPlan);
        final hasConfirmedVotingEligibility =
            state.hasConfirmedVotingEligibility;
        final isVotingEligibilityPending = _isVotingEligibilityPending(state);
        final hasBlockingRecovery = hasBlockingRoundRecoveryWork(
          state.roundPlan,
        );
        _maybePrepareVotingPower(state);
        // Foreground recovery takes precedence over the read-only voted view.
        // Accepted helper shares may still be tracked after submission, but
        // that background work should not keep this screen resumable.
        if (hasBlockingRecovery && hasConfirmedVotingEligibility) {
          return VotingDetailPendingVote(
            roundTitle: round.title.isEmpty
                ? 'Token holder voting'
                : round.title,
            snapshotHeight: round.snapshotHeight,
            description: _roundDescription(round.rawJson),
            forumUri: forumUri,
            roundId: roundId,
            accountUuid: accountUuid,
          );
        }
        if (completedVote != null &&
            (hasConfirmedVotingEligibility || isVotingEligibilityPending)) {
          return VotingDetailVoted(
            roundTitle: round.title.isEmpty
                ? 'Token holder voting'
                : round.title,
            snapshotHeight: round.snapshotHeight,
            description: _roundDescription(round.rawJson),
            forumUri: forumUri,
            votingPowerZatoshi: state.eligibleWeightZatoshi,
            votingPowerPreparing: _votingPowerPreparationInFlight,
            votedAt: completedVote.votedAt,
            proposals: proposals,
            choicesByProposalId: completedVote.choicesByProposalId,
          );
        }
        if (pendingVote != null && hasConfirmedVotingEligibility) {
          return VotingDetailPendingVote(
            roundTitle: round.title.isEmpty
                ? 'Token holder voting'
                : round.title,
            snapshotHeight: round.snapshotHeight,
            description: _roundDescription(round.rawJson),
            forumUri: forumUri,
            roundId: roundId,
            accountUuid: accountUuid,
          );
        }
        if (votingPollListStatus(round.status) != VotingPollListStatus.active &&
            !hasBlockingRecovery) {
          _redirectToResults(round.roundId);
          return const VotingDetailRedirecting();
        }
        final draftKey = accountUuid == null
            ? null
            : VotingSessionKey(roundId: roundId, accountUuid: accountUuid);
        final draft = draftKey == null
            ? const VotingDraftState()
            : ref.watch(votingDraftProvider(draftKey));
        final votingPowerPreparing =
            _votingPowerPreparationInFlight ||
            (state.eligibleWeightZatoshi == null &&
                state.error == null &&
                _shouldPrepareVotingPower(state));
        final votingEligibilityMessage = _votingEligibilityMessage(
          state,
          preparing: votingPowerPreparing,
        );
        final votingError = state.error;
        final votingEligibilityError = votingError == null
            ? false
            : isVotingEligibilityErrorText(votingError.message);
        _maybePrecomputeDelegationPir(state);
        return VotingDetailActive(
          roundId: roundId,
          title: round.title.isEmpty ? 'Token holder voting' : round.title,
          snapshotHeight: round.snapshotHeight,
          description: _roundDescription(round.rawJson),
          forumUri: forumUri,
          endDate: _roundEndDate(round.rawJson),
          votingPowerZatoshi: votingEligibilityError
              ? BigInt.zero
              : state.eligibleWeightZatoshi,
          votingPowerPreparing: votingPowerPreparing,
          votingEligibilityConfirmed: hasConfirmedVotingEligibility,
          votingEligibilityMessage: votingEligibilityError
              ? null
              : votingEligibilityMessage,
          votingEligibilityErrorMessage: votingEligibilityError
              ? votingEligibilityMessage
              : null,
          onVotingEligibilityRetry: _retryVotingPowerPreparation,
          proposals: proposals,
          draft: draft,
          onChoice: draftKey == null
              ? (_, _) {}
              : (proposalId, choice) {
                  if (!hasConfirmedVotingEligibility) return;
                  final notifier = ref.read(
                    votingDraftProvider(draftKey).notifier,
                  );
                  if (choice == null) {
                    notifier.clearChoice(proposalId);
                  } else {
                    notifier.setChoice(proposalId, choice);
                  }
                },
        );
      },
    );
    return widget.builder(context, view);
  }

  void _redirectToResults(String roundId) {
    if (_resultsRedirectRoundId == roundId) return;
    _resultsRedirectRoundId = roundId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(votingResultsRoute(roundId));
    });
  }

  void _maybePrepareVotingPower(
    VotingSessionState state, {
    bool force = false,
  }) {
    final preparationKey = '${widget.roundId}|${state.accountUuid ?? ''}';
    if (_votingPowerPreparationKey != preparationKey) {
      _votingPowerPreparationKey = preparationKey;
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
    }

    final canPrepare = force
        ? _canForcePrepareVotingPower(state)
        : _shouldPrepareVotingPower(state);

    if ((!force && _votingPowerPreparationStarted) ||
        (!force && state.eligibleWeightZatoshi != null) ||
        !canPrepare) {
      return;
    }

    _votingPowerPreparationStarted = true;
    _votingPowerPreparationInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(votingSessionProvider(widget.roundId).notifier)
            .refreshEligibleWeight()
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint(
                '[zcash] Voting: voting eligibility refresh failed '
                'round=${widget.roundId} account=${state.accountUuid} '
                'error=$error',
              );
              return null;
            })
            .whenComplete(() {
              if (!mounted) return;
              setState(() {
                _votingPowerPreparationInFlight = false;
              });
            }),
      );
    });
  }

  void _retryVotingPowerPreparation() {
    if (_votingPowerPreparationInFlight) return;
    final state = ref.read(votingSessionProvider(widget.roundId)).value;
    if (state == null) return;
    setState(() {
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
    });
    _maybePrepareVotingPower(state, force: true);
  }

  // Warm the delegation PIR / padded-note secrets as soon as the round page
  // opens, rather than waiting for the review screen. The warm-up is decoupled
  // from PCZT construction, so it only needs the stored voting hotkey secret.
  void _maybePrecomputeDelegationPir(VotingSessionState state) {
    final accountUuid = state.accountUuid;
    if (accountUuid == null ||
        !state.hasConfirmedVotingEligibility ||
        !_shouldPrepareVotingPower(state)) {
      return;
    }

    final key = '${widget.roundId}|$accountUuid';
    if (_delegationPirPrecomputeKey == key) return;
    _delegationPirPrecomputeKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startDelegationPirPrecompute(accountUuid));
    });
  }

  Future<void> _startDelegationPirPrecompute(String accountUuid) async {
    try {
      await ref
          .read(votingSessionProvider(widget.roundId).notifier)
          .precomputeDelegationPir(accountUuid: accountUuid);
    } catch (e) {
      debugPrint('[zcash] Voting: delegation PIR precompute skipped: $e');
    }
  }
}

bool _shouldPrepareVotingPower(VotingSessionState state) {
  return switch (state.phase) {
    VotingSessionPhase.idle ||
    VotingSessionPhase.delegated ||
    VotingSessionPhase.readyToDelegate ||
    VotingSessionPhase.readyToVote ||
    VotingSessionPhase.submittingShares ||
    VotingSessionPhase.done => true,
    _ => false,
  };
}

bool _canForcePrepareVotingPower(VotingSessionState state) {
  return _shouldPrepareVotingPower(state) ||
      state.phase == VotingSessionPhase.error;
}

bool _isVotingEligibilityPending(VotingSessionState state) {
  return state.eligibleWeightZatoshi == null && state.error == null;
}

String? _votingEligibilityMessage(
  VotingSessionState state, {
  required bool preparing,
}) {
  if (state.hasConfirmedVotingEligibility) {
    return _privacyTrimNotice(state.privacyTrimDroppedValueZatoshi);
  }
  final error = state.error;
  if (error != null) return friendlyVotingErrorText(error.message);
  if (preparing) return null;
  return 'Voting power unavailable.';
}

/// One quiet line for the voters whose voting power the privacy trim reduced.
///
/// Bundle planning drops a low-value tail so a holder does not stand out by the
/// number of delegation submissions they emit. That withheld value is real
/// voting power, so it is stated rather than silently discarded. Most voters
/// have nothing withheld and see nothing.
String? _privacyTrimNotice(BigInt? droppedValueZatoshi) {
  if (droppedValueZatoshi == null || droppedValueZatoshi <= BigInt.zero) {
    return null;
  }
  return '${formatVotingPower(droppedValueZatoshi)} is left out of this vote '
      'to keep your submission less identifiable.';
}

class _CompletedVote {
  const _CompletedVote({
    required this.choicesByProposalId,
    required this.votedAt,
  });

  final Map<int, int?> choicesByProposalId;
  final DateTime? votedAt;

  static _CompletedVote? fromPlan(rust_wire.RoundPlanView? roundPlan) {
    final display = roundPlan?.completedVoteDisplay;
    if (display == null || !hasCompletedVoteForDisplay(roundPlan)) {
      return null;
    }
    final choices = {
      for (final choice in display.choices) choice.proposalId: choice.choice,
    };
    return _CompletedVote(
      choicesByProposalId: choices,
      votedAt: parseFlexibleDate(display.votedAt?.toInt()),
    );
  }
}

class _PendingVoteRecovery {
  const _PendingVoteRecovery({required this.message});

  final String message;

  static _PendingVoteRecovery? fromPlan(rust_wire.RoundPlanView? roundPlan) {
    if (roundPlan == null ||
        !roundPlan.blockingRecovery ||
        !roundPlan.completedVoteArtifact) {
      return null;
    }
    if (roundPlan.primaryAction == 'delegate' ||
        roundPlan.recoveredDelegationWork.isNotEmpty) {
      return const _PendingVoteRecovery(
        message:
            'This vote has local progress, but delegation is not fully confirmed yet. The app should continue recovery before accepting another vote.',
      );
    }
    if (roundPlan.primaryAction == 'vote' ||
        roundPlan.recoveredVoteWork.any(
          (work) => work.kind != 'submit_shares',
        )) {
      return const _PendingVoteRecovery(
        message:
            'This vote has been started, but its commitment transaction recovery data is not complete yet. Do not vote again from this account.',
      );
    }
    return const _PendingVoteRecovery(
      message:
          'This vote was submitted, but some helper-server shares are still waiting for confirmation. Do not vote again from this account.',
    );
  }
}

String _roundDescription(Map<String, dynamic> json) {
  for (final key in const ['description', 'body', 'summary']) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

DateTime? _roundEndDate(Map<String, dynamic> json) {
  return parseFlexibleDate(json['vote_end_time']);
}

/// Body copy of the skip-unanswered-questions confirmation, shared by the
/// desktop dialog and the mobile sheet.
String votingSkippedQuestionsDialogMessage({
  required int skippedCount,
  required int totalCount,
}) {
  return 'You have not answered $skippedCount of $totalCount '
      'questions. The review screen will mark them as skipped, '
      'and skipped questions will not be submitted.';
}
