import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/voting/voting_session_provider.dart';
import '../../providers/voting/voting_state.dart';
import 'voting_error_messages.dart';
import 'voting_flow_models.dart';
import 'voting_poll_ordering.dart';
import 'voting_routes.dart';

/// One renderable state of the review screen. Produced by
/// [VotingReviewFlow]; rendered by the form-factor screens.
sealed class VotingReviewView {
  const VotingReviewView();
}

class VotingReviewLoading extends VotingReviewView {
  const VotingReviewLoading();
}

class VotingReviewMessage extends VotingReviewView {
  const VotingReviewMessage(this.message);

  final String message;
}

/// The round is no longer active; the flow has scheduled a redirect to the
/// results route.
class VotingReviewRedirecting extends VotingReviewView {
  const VotingReviewRedirecting();
}

class VotingReviewContent extends VotingReviewView {
  const VotingReviewContent({
    required this.proposals,
    required this.roundForumUri,
    required this.draft,
    required this.hasConfirmedVotingEligibility,
    required this.eligibilityMessage,
    required this.onSubmit,
  });

  final List<VotingProposalView> proposals;
  final Uri? roundForumUri;
  final VotingDraftState draft;
  final bool hasConfirmedVotingEligibility;
  final String? eligibilityMessage;

  /// Null while submission is not allowed (empty draft or unconfirmed
  /// eligibility).
  final VoidCallback? onSubmit;
}

typedef VotingReviewBuilder =
    Widget Function(BuildContext context, VotingReviewView view);

/// Shared state machine behind the review screens: voting-power preparation,
/// the delegation PIR precompute warm-up, the inactive-round redirect, and
/// the guarded submit action that moves to the status route.
class VotingReviewFlow extends ConsumerStatefulWidget {
  const VotingReviewFlow({
    super.key,
    required this.roundId,
    required this.builder,
  });

  final String roundId;
  final VotingReviewBuilder builder;

  @override
  ConsumerState<VotingReviewFlow> createState() => _VotingReviewFlowState();
}

class _VotingReviewFlowState extends ConsumerState<VotingReviewFlow> {
  bool _precomputeStarted = false;
  bool _votingPowerPreparationStarted = false;
  bool _votingPowerPreparationInFlight = false;
  String? _votingPowerPreparationKey;
  String? _delegationPirPrecomputeKey;
  String? _resultsRedirectRoundId;

  @override
  void didUpdateWidget(covariant VotingReviewFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId != widget.roundId) {
      _precomputeStarted = false;
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
      _votingPowerPreparationKey = null;
      _delegationPirPrecomputeKey = null;
      _resultsRedirectRoundId = null;
    }
  }

  void _maybePrepareVotingPower(VotingSessionState state) {
    final preparationKey = '${widget.roundId}|${state.accountUuid ?? ''}';
    if (_votingPowerPreparationKey != preparationKey) {
      _votingPowerPreparationKey = preparationKey;
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
    }

    if (_votingPowerPreparationStarted ||
        state.eligibleWeightZatoshi != null ||
        !_shouldPrepareVotingPower(state)) {
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
                '[zcash] Voting: review voting eligibility refresh failed '
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

  void _maybePrecomputeDelegationPir(VotingSessionState state) {
    final accountUuid = state.accountUuid;
    if (accountUuid == null || !state.hasConfirmedVotingEligibility) {
      return;
    }

    final key = '${widget.roundId}|$accountUuid';
    if (_delegationPirPrecomputeKey == key) return;
    _precomputeStarted = false;
    _delegationPirPrecomputeKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startPirPrecompute(accountUuid));
    });
  }

  Future<void> _startPirPrecompute(String accountUuid) async {
    if (_precomputeStarted) return;
    _precomputeStarted = true;
    try {
      await ref
          .read(votingSessionProvider(widget.roundId).notifier)
          .precomputeDelegationPir(accountUuid: accountUuid);
    } catch (e) {
      debugPrint('[zcash] Voting: delegation PIR precompute skipped: $e');
    }
  }

  void _redirectToResults(String roundId) {
    if (_resultsRedirectRoundId == roundId) return;
    _resultsRedirectRoundId = roundId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(votingResultsRoute(roundId));
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(votingSessionProvider(widget.roundId));
    final view = session.when(
      skipLoadingOnRefresh: false,
      loading: () => const VotingReviewLoading(),
      error: (error, _) => VotingReviewMessage(
        "Couldn't load review: ${friendlyVotingErrorMessage(error)}",
      ),
      data: (state) {
        final round = state.round;
        if (round != null &&
            votingPollListStatus(round.status) != VotingPollListStatus.active) {
          _redirectToResults(round.roundId);
          return const VotingReviewRedirecting();
        }
        _maybePrepareVotingPower(state);
        _maybePrecomputeDelegationPir(state);
        final proposals = round == null
            ? <VotingProposalView>[]
            : proposalsFromRound(round);
        final roundForumUri = round == null
            ? null
            : votingRoundForumUriFromJson(round.rawJson);
        final accountUuid = state.accountUuid;
        final draft = accountUuid == null
            ? const VotingDraftState()
            : ref.watch(
                votingDraftProvider(
                  VotingSessionKey(
                    roundId: widget.roundId,
                    accountUuid: accountUuid,
                  ),
                ),
              );
        final votingPowerPreparing =
            _votingPowerPreparationInFlight ||
            (state.eligibleWeightZatoshi == null &&
                state.error == null &&
                _shouldPrepareVotingPower(state));
        final eligibilityMessage = _votingEligibilityMessage(
          state,
          preparing: votingPowerPreparing,
        );
        final onSubmit = draft.isEmpty || !state.hasConfirmedVotingEligibility
            ? null
            : () => context.go(
                votingStatusRoute(widget.roundId, accountUuid: accountUuid),
              );
        return VotingReviewContent(
          proposals: proposals,
          roundForumUri: roundForumUri,
          draft: draft,
          hasConfirmedVotingEligibility: state.hasConfirmedVotingEligibility,
          eligibilityMessage: eligibilityMessage,
          onSubmit: onSubmit,
        );
      },
    );
    return widget.builder(context, view);
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

String? _votingEligibilityMessage(
  VotingSessionState state, {
  required bool preparing,
}) {
  if (state.hasConfirmedVotingEligibility) return null;
  final error = state.error;
  if (error != null) return friendlyVotingErrorText(error.message);
  if (preparing) return 'Preparing voting power.';
  return 'Voting power unavailable.';
}
