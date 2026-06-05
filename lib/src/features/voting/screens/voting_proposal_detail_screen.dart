import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/formatting/number_format.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_tree_sync_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_formatters.dart';
import '../voting_poll_ordering.dart';
import '../voting_resume_plan.dart';
import '../voting_routes.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';

class VotingProposalDetailScreen extends ConsumerStatefulWidget {
  const VotingProposalDetailScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingProposalDetailScreen> createState() =>
      _VotingProposalDetailScreenState();
}

class _VotingProposalDetailScreenState
    extends ConsumerState<VotingProposalDetailScreen> {
  bool _votingPowerPreparationStarted = false;
  bool _votingPowerPreparationInFlight = false;
  String? _votingPowerPreparationKey;
  String? _delegationPirPrecomputeKey;
  String? _resultsRedirectRoundId;

  @override
  void didUpdateWidget(covariant VotingProposalDetailScreen oldWidget) {
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
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: session.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              _Message(title: "Couldn't load voting round", message: '$error'),
          data: (state) {
            final round = state.round;
            if (round == null) {
              return const _Message(
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
            final isVotingEligibilityPending = _isVotingEligibilityPending(
              state,
            );
            final hasBlockingRecovery = hasBlockingRoundRecoveryWork(
              state.roundPlan,
            );
            _maybePrepareVotingPower(state);
            // Foreground recovery takes precedence over the read-only voted view.
            // Accepted helper shares may still be tracked after submission, but
            // that background work should not keep this screen resumable.
            if (hasBlockingRecovery && hasConfirmedVotingEligibility) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _PendingVoteContent(
                  roundTitle: round.title.isEmpty
                      ? 'Token holder voting'
                      : round.title,
                  snapshotHeight: round.snapshotHeight,
                  description: _roundDescription(round.rawJson),
                  forumUri: forumUri,
                  roundId: roundId,
                  accountUuid: accountUuid,
                ),
              );
            }
            if (completedVote != null &&
                (hasConfirmedVotingEligibility || isVotingEligibilityPending)) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _VotedPollContent(
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
                ),
              );
            }
            if (pendingVote != null && hasConfirmedVotingEligibility) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _PendingVoteContent(
                  roundTitle: round.title.isEmpty
                      ? 'Token holder voting'
                      : round.title,
                  snapshotHeight: round.snapshotHeight,
                  description: _roundDescription(round.rawJson),
                  forumUri: forumUri,
                  roundId: roundId,
                  accountUuid: accountUuid,
                ),
              );
            }
            if (votingPollListStatus(round.status) !=
                    VotingPollListStatus.active &&
                !hasBlockingRecovery) {
              _redirectToResults(round.roundId);
              return const Center(child: CircularProgressIndicator());
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
            return _ActivePollContent(
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
        ),
      ),
    );
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
  if (state.hasConfirmedVotingEligibility) return null;
  final error = state.error;
  if (error != null) return friendlyVotingErrorText(error.message);
  if (preparing) return null;
  return 'Voting power unavailable.';
}

class _ActivePollContent extends StatefulWidget {
  const _ActivePollContent({
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

  @override
  State<_ActivePollContent> createState() => _ActivePollContentState();
}

class _ActivePollContentState extends State<_ActivePollContent> {
  Future<void> _showIneligibleDialog() async {
    final message = widget.votingEligibilityErrorMessage;
    if (message == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _IneligiblePollDialog(message: message),
    );
  }

  Future<void> _handleBottomActionPressed() async {
    if (_canRetryVotingEligibility) {
      widget.onVotingEligibilityRetry();
      return;
    }
    if (!widget.votingEligibilityConfirmed) {
      await _showIneligibleDialog();
      return;
    }
    final skippedCount = widget.proposals
        .where((proposal) => widget.draft.choices[proposal.id] == null)
        .length;
    if (skippedCount > 0) {
      final continueToReview = await showDialog<bool>(
        context: context,
        builder: (_) => _SkippedQuestionsDialog(
          skippedCount: skippedCount,
          totalCount: widget.proposals.length,
        ),
      );
      if (!mounted || continueToReview != true) return;
    }

    if (mounted) {
      context.push(votingReviewRoute(widget.roundId));
    }
  }

  bool get _canRetryVotingEligibility {
    return !widget.votingEligibilityConfirmed &&
        !widget.votingPowerPreparing &&
        widget.votingEligibilityMessage != null &&
        widget.votingEligibilityErrorMessage == null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
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
          child: widget.proposals.isEmpty
              ? const _Message(
                  title: 'No proposals',
                  message: 'This voting round does not contain any proposals.',
                )
              : VotingPaneListView.separated(
                  maxWidth: 560,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  itemCount: widget.proposals.length + 2,
                  separatorBuilder: (_, index) {
                    final afterSummary = index == 0;
                    final beforeAction = index == widget.proposals.length;
                    return SizedBox(
                      height: afterSummary || beforeAction
                          ? AppSpacing.md
                          : AppSpacing.xs,
                    );
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _PollSummary(
                        title: widget.title,
                        snapshotHeight: widget.snapshotHeight,
                        description: widget.description,
                        forumUri: widget.forumUri,
                        endDate: widget.endDate,
                        votingPowerZatoshi: widget.votingPowerZatoshi,
                        votingPowerPreparing: widget.votingPowerPreparing,
                        votingEligibilityMessage:
                            widget.votingEligibilityMessage,
                      );
                    }
                    if (index == widget.proposals.length + 1) {
                      final canRetryEligibility = _canRetryVotingEligibility;
                      final isIneligible =
                          !widget.votingEligibilityConfirmed &&
                          widget.votingEligibilityErrorMessage != null;
                      return _ReviewAnswersButton(
                        enabled:
                            canRetryEligibility ||
                            isIneligible ||
                            widget.votingEligibilityConfirmed &&
                                !widget.draft.isEmpty,
                        label: canRetryEligibility
                            ? 'Retry eligibility'
                            : isIneligible
                            ? 'Not eligible'
                            : 'Review answers',
                        onPressed: _handleBottomActionPressed,
                      );
                    }
                    final proposal = widget.proposals[index - 1];
                    final isIneligible =
                        !widget.votingEligibilityConfirmed &&
                        widget.votingEligibilityErrorMessage != null;
                    return VotingProposalCard(
                      proposal: proposal,
                      selectedChoice: widget.votingEligibilityConfirmed
                          ? widget.draft.choices[proposal.id]
                          : null,
                      enabled: widget.votingEligibilityConfirmed,
                      onDisabledOptionTap: isIneligible
                          ? _showIneligibleDialog
                          : null,
                      onChoice: (choice) =>
                          widget.onChoice(proposal.id, choice),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SkippedQuestionsDialog extends StatelessWidget {
  const _SkippedQuestionsDialog({
    required this.skippedCount,
    required this.totalCount,
  });

  final int skippedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.background.neutralSubtleOpacity,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.warning,
                        size: AppIconSize.medium,
                        color: colors.icon.regular,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Skip unanswered questions?',
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'You have not answered $skippedCount of $totalCount '
                'questions. The review screen will mark them as skipped, '
                'and skipped questions will not be submitted.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                onPressed: () => Navigator.of(context).pop(true),
                minWidth: 312,
                child: const Text('Continue to review'),
              ),
              const SizedBox(height: AppSpacing.s),
              AppButton(
                onPressed: () => Navigator.of(context).pop(false),
                variant: AppButtonVariant.ghost,
                minWidth: 312,
                child: const Text('Keep voting'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IneligiblePollDialog extends StatelessWidget {
  const _IneligiblePollDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.background.neutralSubtleOpacity,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.warning,
                        size: AppIconSize.medium,
                        color: colors.icon.regular,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Not eligible for this voting round',
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                onPressed: () => Navigator.of(context).pop(),
                minWidth: 312,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PollSummary extends StatelessWidget {
  const _PollSummary({
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.endDate,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votingEligibilityMessage,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final DateTime? endDate;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final String? votingEligibilityMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasDescription = description.isNotEmpty;
    final descriptionStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
      height: 20 / 14,
      letterSpacing: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    height: 30 / 20,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '#${formatGroupedInteger(snapshotHeight)}',
                style: AppTypography.headlineMedium.copyWith(
                  color: colors.text.accent,
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  height: 30 / 20,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetaText(
              endDate == null
                  ? 'Voting active'
                  : 'Ends ${formatMonthDayYear(endDate!)}',
            ),
            const _MetaText('·'),
            _VotingPowerMeta(
              zatoshi: votingPowerZatoshi,
              preparing: votingPowerPreparing,
            ),
            if (endDate != null) ...[
              const _MetaText('·'),
              _MetaText(_daysLeftLabel(endDate!)),
            ],
          ],
        ),
        if (votingEligibilityMessage != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            votingEligibilityMessage!,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
              height: 16 / 12,
              letterSpacing: 0,
            ),
          ),
        ],
        if (hasDescription) ...[
          const SizedBox(height: AppSpacing.xs),
          VotingExpandableText(text: description, style: descriptionStyle),
        ],
        if (forumUri != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: VotingForumLinkButton(uri: forumUri!),
          ),
        ],
      ],
    );
  }
}

class _ReviewAnswersButton extends StatelessWidget {
  const _ReviewAnswersButton({
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AppButton(
          onPressed: enabled ? onPressed : null,
          variant: AppButtonVariant.primary,
          size: AppButtonSize.large,
          minWidth: constraints.maxWidth,
          child: Text(label),
        );
      },
    );
  }
}

class _VotedPollContent extends StatelessWidget {
  const _VotedPollContent({
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppRouteBackLink(),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _VotedPollHeader(
                title: roundTitle,
                snapshotHeight: snapshotHeight,
                description: description,
                forumUri: forumUri,
                votingPowerZatoshi: votingPowerZatoshi,
                votingPowerPreparing: votingPowerPreparing,
                votedAt: votedAt,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: proposals.isEmpty
              ? const _Message(
                  title: 'No proposals',
                  message: 'This voting round does not contain any proposals.',
                )
              : VotingPaneListView.separated(
                  maxWidth: 560,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  itemCount: proposals.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s),
                  itemBuilder: (context, index) {
                    final proposal = proposals[index];
                    final choice = choicesByProposalId[proposal.id];
                    return VotingProposalCard(
                      proposal: proposal,
                      fallbackForumUri: forumUri,
                      selectedChoice: choice,
                      readOnly: true,
                      statusLabel: choice == null ? 'Skipped' : null,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PendingVoteContent extends StatelessWidget {
  const _PendingVoteContent({
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
        const Spacer(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.background.base,
                borderRadius: BorderRadius.circular(AppRadii.large),
                border: Border.all(color: colors.border.subtle),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          roundTitle,
                          style: AppTypography.headlineMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '#${formatGroupedInteger(snapshotHeight)}',
                        style: AppTypography.headlineSmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    VotingExpandableText(
                      text: description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  if (forumUri != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: VotingForumLinkButton(uri: forumUri!),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Vote in progress',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'You have an unfinished vote for this round. '
                    'Resume to complete the submission.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    onPressed: () => context.go(
                      votingStatusRoute(roundId, accountUuid: accountUuid),
                    ),
                    variant: AppButtonVariant.primary,
                    child: const Text('Continue voting'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _VotedPollHeader extends StatelessWidget {
  const _VotedPollHeader({
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votedAt,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final DateTime? votedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.headlineMedium.copyWith(
      color: colors.text.accent,
      fontFamily: 'Geist',
      fontWeight: FontWeight.w600,
      fontSize: 20,
      height: 30 / 20,
      letterSpacing: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: titleStyle)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${formatGroupedInteger(snapshotHeight)}',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            _MetaText(
              votedAt == null
                  ? 'Voted'
                  : 'Voted ${formatMonthDayYear(votedAt!)}',
            ),
            const _MetaText('·'),
            _VotingPowerMeta(
              zatoshi: votingPowerZatoshi,
              preparing: votingPowerPreparing,
            ),
            const _MetaText('·'),
            const _MetaText('Vote locked'),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          VotingExpandableText(
            text: description,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (forumUri != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: VotingForumLinkButton(uri: forumUri!),
          ),
        ],
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.secondary,
        height: 16 / 12,
        letterSpacing: 0,
      ),
    );
  }
}

class _VotingPowerMeta extends StatelessWidget {
  const _VotingPowerMeta({required this.zatoshi, required this.preparing});

  final BigInt? zatoshi;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final votingPower = zatoshi;
    if (votingPower == null) {
      if (!preparing) {
        return const _MetaText('Voting power unavailable');
      }
      final colors = context.colors;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colors.icon.regular,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          const _MetaText('Preparing voting power'),
        ],
      );
    }
    return _MetaText('Voting power ${formatVotingPower(votingPower)}');
  }
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

String _daysLeftLabel(DateTime endDate) {
  final now = DateTime.now();
  final localEnd = endDate.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final endDay = DateTime(localEnd.year, localEnd.month, localEnd.day);
  final days = endDay.difference(today).inDays;
  if (days <= 0) return 'Ends today';
  if (days == 1) return '1 day left';
  return '$days days left';
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title\n$message',
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.accent,
        ),
      ),
    );
  }
}
