import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_poll_ordering.dart';
import '../voting_routes.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';

const _mobileReviewActionExtent =
    AppSpacing.xs + AppButtonSizing.largeHeight + AppSpacing.md;
const _mobileReviewScrollBottomPadding =
    _mobileReviewActionExtent + AppSpacing.md;

class VotingReviewScreen extends StatelessWidget {
  const VotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: VotingReviewView(roundId: roundId, showDesktopToolbar: true),
      ),
    );
  }
}

class VotingReviewView extends ConsumerStatefulWidget {
  const VotingReviewView({
    required this.roundId,
    required this.showDesktopToolbar,
    super.key,
  });

  final String roundId;
  final bool showDesktopToolbar;

  @override
  ConsumerState<VotingReviewView> createState() => _VotingReviewViewState();
}

class _VotingReviewViewState extends ConsumerState<VotingReviewView> {
  bool _snapshotPrecomputeStarted = false;
  bool _votingPowerPreparationStarted = false;
  bool _votingPowerPreparationInFlight = false;
  String? _votingPowerPreparationKey;
  String? _snapshotBundlePrecomputeKey;
  String? _resultsRedirectRoundId;

  @override
  void didUpdateWidget(covariant VotingReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId != widget.roundId) {
      _snapshotPrecomputeStarted = false;
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
      _votingPowerPreparationKey = null;
      _snapshotBundlePrecomputeKey = null;
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

  void _maybePrecomputeSnapshotBundles(VotingSessionState state) {
    final accountUuid = state.accountUuid;
    if (accountUuid == null || !state.hasConfirmedVotingEligibility) {
      return;
    }

    final key = '${widget.roundId}|$accountUuid';
    if (_snapshotBundlePrecomputeKey == key) return;
    _snapshotPrecomputeStarted = false;
    _snapshotBundlePrecomputeKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startSnapshotBundlePrecompute(accountUuid));
    });
  }

  Future<void> _startSnapshotBundlePrecompute(String accountUuid) async {
    if (_snapshotPrecomputeStarted) return;
    _snapshotPrecomputeStarted = true;
    try {
      await ref
          .read(votingSessionProvider(widget.roundId).notifier)
          .precomputeSnapshotBundles(accountUuid: accountUuid);
    } catch (e) {
      debugPrint('[zcash] Voting: snapshot bundle precompute skipped: $e');
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
    return session.when(
      skipLoadingOnRefresh: false,
      loading: () => _stateView(const VotingPaneLoading()),
      error: (error, _) => _stateView(
        _Message("Couldn't load review: ${friendlyVotingErrorMessage(error)}"),
      ),
      data: (state) {
        final round = state.round;
        if (round != null &&
            votingPollListStatus(round.status) != VotingPollListStatus.active) {
          _redirectToResults(round.roundId);
          return _stateView(const VotingPaneLoading());
        }
        _maybePrepareVotingPower(state);
        _maybePrecomputeSnapshotBundles(state);
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
        final reportedBundleCount =
            state.bundleCount ?? state.resumePlan?.bundleCount;
        final bundleCount =
            reportedBundleCount != null && reportedBundleCount > 0
            ? reportedBundleCount
            : null;
        final onSubmit = draft.isEmpty || !state.hasConfirmedVotingEligibility
            ? null
            : () {
                final route = votingStatusRoute(
                  widget.roundId,
                  accountUuid: accountUuid,
                );
                if (widget.showDesktopToolbar) {
                  context.go(route);
                } else {
                  context.pushReplacement(route);
                }
              };
        final reviewContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showDesktopToolbar) ...[
              Text(
                'Review your answers',
                textAlign: TextAlign.center,
                style: AppTypography.displaySmall.copyWith(
                  color: context.colors.text.accent,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (state.hasConfirmedVotingEligibility) ...[
              _Message(
                bundleCount == null
                    ? 'Preparing voting bundle count.'
                    : 'This submission will use $bundleCount voting '
                          '${bundleCount == 1 ? 'bundle' : 'bundles'}.',
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
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
            if (state.hasConfirmedVotingEligibility && draft.isEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              const _Message('Choose at least one option before submitting.'),
            ],
            if (eligibilityMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _Message(eligibilityMessage),
            ],
          ],
        );
        final submitButton = AppButton(
          key: const ValueKey('voting_confirm_submit_button'),
          onPressed: onSubmit,
          variant: AppButtonVariant.primary,
          minWidth: widget.showDesktopToolbar ? 240 : null,
          expand: !widget.showDesktopToolbar,
          child: const Text('Confirm & submit'),
        );
        if (!widget.showDesktopToolbar) {
          return Stack(
            fit: StackFit.expand,
            children: [
              VotingPaneScrollView(
                key: const ValueKey('mobile_voting_review_scroll'),
                maxWidth: 560,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  0,
                ),
                scrollPadding: const EdgeInsets.only(
                  bottom: _mobileReviewScrollBottomPadding,
                ),
                child: reviewContent,
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Padding(
                  key: const ValueKey('mobile_voting_review_action'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: submitButton,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(backLinkMinWidth: 60),
            Expanded(
              child: VotingPaneScrollView(
                maxWidth: 560,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: reviewContent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Center(child: submitButton),
            ),
          ],
        );
      },
    );
  }

  Widget _stateView(Widget child) {
    if (!widget.showDesktopToolbar) return child;
    return VotingPaneStateView(backLinkMinWidth: 60, child: child);
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
