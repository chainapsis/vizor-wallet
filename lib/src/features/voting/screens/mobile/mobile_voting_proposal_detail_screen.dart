import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/formatting/number_format.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/layout/mobile/mobile_top_scroll_fade.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../voting_proposal_detail_flow.dart';
import '../../voting_routes.dart';
import '../../widgets/voting_detail_widgets.dart';
import '../../widgets/voting_metadata_widgets.dart';

/// Mobile proposal detail: the questions and choices of one voting round.
/// Thin shell over [VotingProposalDetailFlow]; confirmation dialogs become
/// bottom sheets.
class MobileVotingProposalDetailScreen extends ConsumerStatefulWidget {
  const MobileVotingProposalDetailScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<MobileVotingProposalDetailScreen> createState() =>
      _MobileVotingProposalDetailScreenState();
}

class _MobileVotingProposalDetailScreenState
    extends ConsumerState<MobileVotingProposalDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        bottom: false,
        child: VotingProposalDetailFlow(
          roundId: widget.roundId,
          builder: (context, view) => Column(
            children: [
              MobileTopNav.back(title: 'Vote', onBack: _goBack),
              Expanded(
                child: switch (view) {
                  VotingDetailLoading() || VotingDetailRedirecting() =>
                    const Center(child: CircularProgressIndicator()),
                  VotingDetailMessage(:final title, :final message) =>
                    _CenteredMessage(title: title, message: message),
                  VotingDetailPendingVote() => _PendingVoteBody(view: view),
                  VotingDetailVoted() => _VotedBody(view: view),
                  VotingDetailActive() => _ActiveBody(
                    view: view,
                    onReviewPressed: () =>
                        unawaited(_handleReviewPressed(view)),
                    onDisabledOptionTap: (message) =>
                        unawaited(_showIneligibleSheet(message)),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleReviewPressed(VotingDetailActive view) async {
    final canRetryEligibility = _canRetryVotingEligibility(view);
    if (canRetryEligibility) {
      view.onVotingEligibilityRetry();
      return;
    }
    if (!view.votingEligibilityConfirmed) {
      final message = view.votingEligibilityErrorMessage;
      if (message != null) await _showIneligibleSheet(message);
      return;
    }
    final skippedCount = view.proposals
        .where((proposal) => view.draft.choices[proposal.id] == null)
        .length;
    if (skippedCount > 0) {
      final continueToReview = await showAppMobileSheet<bool>(
        context: context,
        builder: (_) => _SkippedQuestionsSheet(
          skippedCount: skippedCount,
          totalCount: view.proposals.length,
        ),
      );
      if (!mounted || continueToReview != true) return;
    }
    if (mounted) {
      context.push(votingReviewRoute(widget.roundId));
    }
  }

  Future<void> _showIneligibleSheet(String message) {
    return showAppMobileSheet<void>(
      context: context,
      builder: (_) => _IneligiblePollSheet(message: message),
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/voting');
  }
}

bool _canRetryVotingEligibility(VotingDetailActive view) {
  return !view.votingEligibilityConfirmed &&
      !view.votingPowerPreparing &&
      view.votingEligibilityMessage != null &&
      view.votingEligibilityErrorMessage == null;
}

class _ActiveBody extends StatelessWidget {
  const _ActiveBody({
    required this.view,
    required this.onReviewPressed,
    required this.onDisabledOptionTap,
  });

  final VotingDetailActive view;
  final VoidCallback onReviewPressed;
  final void Function(String message) onDisabledOptionTap;

  @override
  Widget build(BuildContext context) {
    if (view.proposals.isEmpty) {
      return const _CenteredMessage(
        title: 'No proposals',
        message: 'This voting round does not contain any proposals.',
      );
    }
    final canRetryEligibility = _canRetryVotingEligibility(view);
    final isIneligible =
        !view.votingEligibilityConfirmed &&
        view.votingEligibilityErrorMessage != null;
    return Column(
      children: [
        Expanded(
          child: MobileTopScrollFade(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                0,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              itemCount: view.proposals.length + 1,
              separatorBuilder: (_, index) => SizedBox(
                height: index == 0 ? AppSpacing.md : AppSpacing.xs,
              ),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return VotingPollSummary(
                    title: view.title,
                    snapshotHeight: view.snapshotHeight,
                    description: view.description,
                    forumUri: view.forumUri,
                    endDate: view.endDate,
                    votingPowerZatoshi: view.votingPowerZatoshi,
                    votingPowerPreparing: view.votingPowerPreparing,
                    votingEligibilityMessage: view.votingEligibilityMessage,
                  );
                }
                final proposal = view.proposals[index - 1];
                return VotingProposalCard(
                  proposal: proposal,
                  selectedChoice: view.votingEligibilityConfirmed
                      ? view.draft.choices[proposal.id]
                      : null,
                  enabled: view.votingEligibilityConfirmed,
                  onDisabledOptionTap: isIneligible
                      ? () => onDisabledOptionTap(
                          view.votingEligibilityErrorMessage!,
                        )
                      : null,
                  onChoice: (choice) => view.onChoice(proposal.id, choice),
                );
              },
            ),
          ),
        ),
        MobileBottomSafeArea(
          bottomPadding: AppSpacing.md,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: AppButton(
                key: const ValueKey('voting_review_answers_button'),
                onPressed:
                    canRetryEligibility ||
                        isIneligible ||
                        view.votingEligibilityConfirmed && !view.draft.isEmpty
                    ? onReviewPressed
                    : null,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.large,
                child: Text(
                  canRetryEligibility
                      ? 'Retry eligibility'
                      : isIneligible
                      ? 'Not eligible'
                      : 'Review answers',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VotedBody extends StatelessWidget {
  const _VotedBody({required this.view});

  final VotingDetailVoted view;

  @override
  Widget build(BuildContext context) {
    if (view.proposals.isEmpty) {
      return const _CenteredMessage(
        title: 'No proposals',
        message: 'This voting round does not contain any proposals.',
      );
    }
    return MobileTopScrollFade(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        itemCount: view.proposals.length + 1,
        separatorBuilder: (_, index) => SizedBox(
          height: index == 0 ? AppSpacing.md : AppSpacing.s,
        ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return VotingVotedPollHeader(
              title: view.roundTitle,
              snapshotHeight: view.snapshotHeight,
              description: view.description,
              forumUri: view.forumUri,
              votingPowerZatoshi: view.votingPowerZatoshi,
              votingPowerPreparing: view.votingPowerPreparing,
              votedAt: view.votedAt,
            );
          }
          final proposal = view.proposals[index - 1];
          final choice = view.choicesByProposalId[proposal.id];
          return VotingProposalCard(
            proposal: proposal,
            fallbackForumUri: view.forumUri,
            selectedChoice: choice,
            readOnly: true,
            statusLabel: choice == null ? 'Skipped' : null,
          );
        },
      ),
    );
  }
}

class _PendingVoteBody extends StatelessWidget {
  const _PendingVoteBody({required this.view});

  final VotingDetailPendingVote view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Center(
        child: SingleChildScrollView(
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
                        view.roundTitle,
                        style: AppTypography.headlineMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '#${formatGroupedInteger(view.snapshotHeight)}',
                      style: AppTypography.headlineSmall.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ],
                ),
                if (view.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  VotingExpandableText(
                    text: view.description,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
                if (view.forumUri != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: VotingForumLinkButton(uri: view.forumUri!),
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
                    votingStatusRoute(
                      view.roundId,
                      accountUuid: view.accountUuid,
                    ),
                  ),
                  variant: AppButtonVariant.primary,
                  child: const Text('Continue voting'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkippedQuestionsSheet extends StatelessWidget {
  const _SkippedQuestionsSheet({
    required this.skippedCount,
    required this.totalCount,
  });

  final int skippedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
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
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            votingSkippedQuestionsDialogMessage(
              skippedCount: skippedCount,
              totalCount: totalCount,
            ),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue to review'),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: () => Navigator.of(context).pop(false),
            variant: AppButtonVariant.ghost,
            child: const Text('Keep voting'),
          ),
        ],
      ),
    );
  }
}

class _IneligiblePollSheet extends StatelessWidget {
  const _IneligiblePollSheet({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
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
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
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
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
