import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/proxy_delegation_feature_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/navigation/route_owned_redirect.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/untranslated_details.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../proxy/proxy_delegation_providers.dart';
import '../proxy/screens/proxy_ballot_review.dart';
import '../proxy/screens/proxy_round_delegation.dart';
import '../proxy/widgets/proxy_delegate_widgets.dart';
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_message.dart';
import '../voting_poll_ordering.dart';
import '../voting_resume_plan.dart';
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

class _VotingReviewViewState extends ConsumerState<VotingReviewView>
    with WidgetsBindingObserver {
  bool _snapshotPrecomputeStarted = false;
  bool _votingPowerPreparationStarted = false;
  bool _votingPowerPreparationInFlight = false;
  String? _votingPowerPreparationKey;
  String? _snapshotBundlePrecomputeKey;

  /// The finality checkbox of a ballot that carries a delegation.
  bool _delegationAcknowledged = false;
  bool _submittingDelegation = false;
  String? _delegationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final session = ref.read(votingSessionProvider(widget.roundId)).value;
    if (session != null) _maybePrecomputeSnapshotBundles(session);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VotingReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId != widget.roundId) {
      _snapshotPrecomputeStarted = false;
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
      _votingPowerPreparationKey = null;
      _snapshotBundlePrecomputeKey = null;
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
      final result = await ref
          .read(votingSessionProvider(widget.roundId).notifier)
          .precomputeSnapshotBundles(accountUuid: accountUuid);
      if (mounted &&
          _snapshotBundlePrecomputeKey == '${widget.roundId}|$accountUuid' &&
          result.shouldRearm) {
        _snapshotPrecomputeStarted = false;
        _snapshotBundlePrecomputeKey = null;
      }
    } catch (e) {
      if (mounted &&
          _snapshotBundlePrecomputeKey == '${widget.roundId}|$accountUuid') {
        _snapshotPrecomputeStarted = false;
        _snapshotBundlePrecomputeKey = null;
      }
      debugPrint('[zcash] Voting: snapshot bundle precompute skipped: $e');
    }
  }

  Widget _resultsRedirect(VotingSessionState snapshot) {
    // Wake an intent blocked by account refresh or locking even when the
    // voting session itself did not publish a different snapshot.
    ref.watch(accountProvider);
    ref.watch(appSecurityProvider.select((state) => state.requiresUnlock));
    return RouteOwnedRedirect(
      requestKey: (widget.roundId, snapshot.accountUuid),
      isValid: () {
        final session = ref.read(votingSessionProvider(widget.roundId));
        final account = ref.read(accountProvider);
        return !ref.read(appSecurityProvider).requiresUnlock &&
            !session.isLoading &&
            !session.hasError &&
            !account.isLoading &&
            !account.hasError &&
            identical(session.value, snapshot) &&
            account.value?.activeAccountUuid == snapshot.accountUuid;
      },
      onNavigate: () => context.go(votingResultsRoute(widget.roundId)),
      child: _stateView(const VotingPaneLoading()),
    );
  }

  /// Commits the drafted delegation with the kept share's [answers], starts
  /// the job carrying the ballot and opens its progress at [route].
  Future<void> _submitDelegation({
    required VotingSessionKey key,
    required List<VotingDraftVote> answers,
    required List<int> proposalIds,
    required String route,
  }) async {
    setState(() {
      _submittingDelegation = true;
      _delegationError = null;
    });
    final error = await submitProxyBallot(
      context.l10n,
      ProviderScope.containerOf(context, listen: false),
      key: key,
      answers: answers,
      proposalIds: proposalIds,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _submittingDelegation = false;
        _delegationError = error;
      });
      return;
    }
    _openProgress(route);
  }

  /// Opens the submission's progress at [route].
  void _openProgress(String route) {
    if (widget.showDesktopToolbar) {
      context.go(route);
    } else {
      context.pushReplacement(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(votingSessionProvider(widget.roundId));
    return session.when(
      skipLoadingOnRefresh: false,
      loading: () => _stateView(const VotingPaneLoading()),
      error: (error, _) => _stateView(
        _Message(
          context.l10n.votingReviewLoadFailed(
            friendlyVotingLoadErrorMessage(context.l10n, error),
          ),
          details: friendlyVotingErrorDetails(error),
        ),
      ),
      data: (state) {
        final round = state.round;
        if (round != null &&
            votingPollListStatus(round.status) != VotingPollListStatus.active) {
          return _resultsRedirect(state);
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
          context.l10n,
          state,
          preparing: votingPowerPreparing,
        );
        // Delegates took every bundle's weight: no ballot is offered.
        final nothingLeftToVote = roundPlanNothingLeftToVote(state.roundPlan);
        final route = votingStatusRoute(
          widget.roundId,
          accountUuid: accountUuid,
        );
        // A delegation drafted on the round screen is reviewed and submitted
        // with the answers. Null with the dormant flag off.
        final delegationKey =
            accountUuid != null &&
                ref.watch(proxyDelegationFeatureEnabledProvider)
            ? VotingSessionKey(
                roundId: widget.roundId,
                accountUuid: accountUuid,
              )
            : null;
        final delegation = delegationKey == null
            ? null
            : ref.watch(proxyBallotDelegationProvider(delegationKey));
        final drafted = delegation != null && !delegation.committed;
        final readiness = drafted
            ? watchProxyDelegationReadiness(ref, delegationKey!)
            : null;
        final everythingDelegated = drafted && delegation.everythingDelegated;
        // A delegation that keeps a share is submitted with its answers.
        final keptShareUnanswered =
            readiness != null && !everythingDelegated && draft.isEmpty;
        final VoidCallback? onSubmit;
        if (readiness != null) {
          onSubmit =
              delegationKey == null ||
                  !readiness.ready ||
                  !_delegationAcknowledged ||
                  _submittingDelegation ||
                  keptShareUnanswered ||
                  !state.hasConfirmedVotingEligibility ||
                  nothingLeftToVote
              ? null
              : () => unawaited(
                  _submitDelegation(
                    key: delegationKey,
                    answers: everythingDelegated
                        ? const []
                        : draft.toDraftVotes(proposals),
                    proposalIds: [for (final p in proposals) p.id],
                    route: route,
                  ),
                );
        } else {
          onSubmit =
              draft.isEmpty ||
                  !state.hasConfirmedVotingEligibility ||
                  nothingLeftToVote
              ? null
              : () => _openProgress(route);
        }
        final reviewContent = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showDesktopToolbar) ...[
              Text(
                context.l10n.votingReviewTitle,
                textAlign: TextAlign.center,
                style: AppTypography.displaySmall.copyWith(
                  color: context.colors.text.accent,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (readiness != null) ...[
              ProxyReviewDelegation(
                readiness: readiness,
                onRetryChecks: () =>
                    ref.invalidate(proxyDelegateChecksProvider(delegationKey!)),
                onRetryRound: () =>
                    ref.invalidate(proxyRoundContextProvider(delegationKey!)),
              ),
              const SizedBox(height: AppSpacing.md),
              if (everythingDelegated)
                ProxyAnswersForYou(names: delegation.names)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    context.l10n.proxyReviewAnswersTitle,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: context.colors.text.accent,
                    ),
                  ),
                ),
            ],
            if (state.hasConfirmedVotingEligibility && !everythingDelegated)
              for (final entry in proposals.asMap().entries) ...[
                VotingProposalCard(
                  proposal: entry.value,
                  fallbackForumUri: roundForumUri,
                  selectedChoice: draft.choices[entry.value.id],
                  readOnly: true,
                  statusLabel: draft.choices[entry.value.id] == null
                      ? context.l10n.votingReviewSkipped
                      : null,
                  titleCollapsedMaxLines: 1,
                ),
                if (entry.key != proposals.length - 1)
                  const SizedBox(height: AppSpacing.s),
              ],
            if (nothingLeftToVote) ...[
              const SizedBox(height: AppSpacing.xs),
              _Message(context.l10n.proxyNothingLeftToVote),
            ] else if (state.hasConfirmedVotingEligibility &&
                draft.isEmpty &&
                (readiness == null || keptShareUnanswered)) ...[
              const SizedBox(height: AppSpacing.xs),
              _Message(
                keptShareUnanswered
                    ? context.l10n.proxyAnswerKeptShare
                    : context.l10n.votingReviewChooseOne,
              ),
            ],
            if (eligibilityMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _Message(eligibilityMessage),
            ],
            if (readiness != null) ...[
              const SizedBox(height: AppSpacing.md),
              const ProxyBeforeYouDelegate(),
            ],
          ],
        );
        final submitButton = AppButton(
          key: const ValueKey('voting_confirm_submit_button'),
          onPressed: onSubmit,
          variant: AppButtonVariant.primary,
          minWidth: widget.showDesktopToolbar ? 240 : null,
          expand: !widget.showDesktopToolbar,
          child: Text(context.l10n.votingReviewConfirmSubmit),
        );
        if (readiness != null) {
          return ProxyPaneLayout(
            showDesktopToolbar: widget.showDesktopToolbar,
            title: null,
            action: ProxyConfirmFooter(
              acknowledged: _delegationAcknowledged,
              error: _delegationError,
              onAcknowledgedChanged: (value) =>
                  setState(() => _delegationAcknowledged = value),
              button: AppButton(
                key: const ValueKey('voting_confirm_submit_button'),
                onPressed: onSubmit,
                variant: AppButtonVariant.primary,
                expand: true,
                growWithContent: true,
                constrainContent: true,
                child: Text(context.l10n.votingReviewConfirmSubmit),
              ),
            ),
            child: reviewContent,
          );
        }
        if (!widget.showDesktopToolbar) {
          return Stack(
            fit: StackFit.expand,
            children: [
              VotingPaneScrollView(
                key: const ValueKey('mobile_voting_review_scroll'),
                maxWidth: 560,
                padding: const EdgeInsets.fromLTRB(
                  kMobilePageMargin,
                  AppSpacing.s,
                  kMobilePageMargin,
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
                    kMobilePageMargin,
                    AppSpacing.xs,
                    kMobilePageMargin,
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
  AppLocalizations l10n,
  VotingSessionState state, {
  required bool preparing,
}) {
  if (state.hasConfirmedVotingEligibility) return null;
  final error = state.error;
  if (error != null) return normalizedVotingMessage(error.message).text(l10n);
  if (preparing) return l10n.votingPreparingPower;
  return l10n.votingPowerUnavailableSentence;
}

class _Message extends StatelessWidget {
  const _Message(this.message, {this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
          ...untranslatedDetailsButton(details),
        ],
      ),
    );
  }
}
