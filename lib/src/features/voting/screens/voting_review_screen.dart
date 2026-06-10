import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_poll_ordering.dart';
import '../voting_routes.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';

class VotingReviewScreen extends ConsumerStatefulWidget {
  const VotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingReviewScreen> createState() => _VotingReviewScreenState();
}

class _VotingReviewScreenState extends ConsumerState<VotingReviewScreen> {
  bool _precomputeStarted = false;
  bool _votingPowerPreparationStarted = false;
  bool _votingPowerPreparationInFlight = false;
  String? _votingPowerPreparationKey;
  String? _delegationPirPrecomputeKey;
  String? _resultsRedirectRoundId;

  @override
  void didUpdateWidget(covariant VotingReviewScreen oldWidget) {
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
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: session.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Message("Couldn't load review: $error"),
          data: (state) {
            final round = state.round;
            if (round != null &&
                votingPollListStatus(round.status) !=
                    VotingPollListStatus.active) {
              _redirectToResults(round.roundId);
              return const Center(child: CircularProgressIndicator());
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
            final onSubmit =
                draft.isEmpty || !state.hasConfirmedVotingEligibility
                ? null
                : () => context.go(
                    votingStatusRoute(widget.roundId, accountUuid: accountUuid),
                  );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  // Design: back chevron sits 16px into the pane on every
                  // top toolbar.
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppRouteBackLink(minWidth: 60),
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
                Expanded(
                  child: VotingPaneScrollView(
                    maxWidth: 560,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Review your answers',
                          textAlign: TextAlign.center,
                          style: AppTypography.displaySmall.copyWith(
                            color: context.colors.text.accent,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (state.hasConfirmedVotingEligibility)
                          for (final entry in proposals.asMap().entries) ...[
                            VotingProposalCard(
                              proposal: entry.value,
                              fallbackForumUri: roundForumUri,
                              selectedChoice: draft.choices[entry.value.id],
                              readOnly: true,
                              statusLabel: draft.choices[entry.value.id] == null
                                  ? 'Skipped'
                                  : null,
                              titleCollapsedMaxLines: 1,
                            ),
                            if (entry.key != proposals.length - 1)
                              const SizedBox(height: AppSpacing.s),
                          ],
                        if (state.hasConfirmedVotingEligibility &&
                            draft.isEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          const _Message(
                            'Choose at least one option before submitting.',
                          ),
                        ],
                        if (eligibilityMessage != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _Message(eligibilityMessage),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xs,
                    bottom: AppSpacing.md,
                  ),
                  child: Center(
                    child: AppButton(
                      onPressed: onSubmit,
                      variant: AppButtonVariant.primary,
                      minWidth: 240,
                      child: const Text('Confirm & submit'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}
