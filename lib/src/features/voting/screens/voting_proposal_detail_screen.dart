import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/number_format.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../voting_proposal_detail_flow.dart';
import '../voting_routes.dart';
import '../widgets/voting_detail_widgets.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';

class VotingProposalDetailScreen extends StatelessWidget {
  const VotingProposalDetailScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: VotingProposalDetailFlow(
          roundId: roundId,
          builder: (context, view) => switch (view) {
            VotingDetailLoading() || VotingDetailRedirecting() =>
              const VotingPaneStateView(
                backLinkMinWidth: 60,
                child: VotingPaneLoading(),
              ),
            VotingDetailMessage(:final title, :final message) =>
              VotingPaneStateView(
                backLinkMinWidth: 60,
                child: _Message(title: title, message: message),
              ),
            VotingDetailPendingVote() => _PendingVoteContent(view: view),
            VotingDetailVoted() => _VotedPollContent(view: view),
            VotingDetailActive() => _ActivePollContent(view: view),
          },
        ),
      ),
    );
  }
}

class _ActivePollContent extends StatefulWidget {
  const _ActivePollContent({required this.view});

  final VotingDetailActive view;

  @override
  State<_ActivePollContent> createState() => _ActivePollContentState();
}

class _ActivePollContentState extends State<_ActivePollContent> {
  VotingDetailActive get view => widget.view;

  Future<void> _showIneligibleDialog() async {
    final message = view.votingEligibilityErrorMessage;
    if (message == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _IneligiblePollDialog(message: message),
    );
  }

  Future<void> _handleBottomActionPressed() async {
    if (_canRetryVotingEligibility) {
      view.onVotingEligibilityRetry();
      return;
    }
    if (!view.votingEligibilityConfirmed) {
      await _showIneligibleDialog();
      return;
    }
    final skippedCount = view.proposals
        .where((proposal) => view.draft.choices[proposal.id] == null)
        .length;
    if (skippedCount > 0) {
      final continueToReview = await showDialog<bool>(
        context: context,
        builder: (_) => _SkippedQuestionsDialog(
          skippedCount: skippedCount,
          totalCount: view.proposals.length,
        ),
      );
      if (!mounted || continueToReview != true) return;
    }

    if (mounted) {
      context.push(votingReviewRoute(view.roundId));
    }
  }

  bool get _canRetryVotingEligibility {
    return !view.votingEligibilityConfirmed &&
        !view.votingPowerPreparing &&
        view.votingEligibilityMessage != null &&
        view.votingEligibilityErrorMessage == null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPaneToolbar(backLinkMinWidth: 60),
        Expanded(
          child: view.proposals.isEmpty
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
                  itemCount: view.proposals.length + 2,
                  separatorBuilder: (_, index) {
                    final afterSummary = index == 0;
                    final beforeAction = index == view.proposals.length;
                    return SizedBox(
                      height: afterSummary || beforeAction
                          ? AppSpacing.md
                          : AppSpacing.xs,
                    );
                  },
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
                        votingEligibilityMessage:
                            view.votingEligibilityMessage,
                      );
                    }
                    if (index == view.proposals.length + 1) {
                      final canRetryEligibility = _canRetryVotingEligibility;
                      final isIneligible =
                          !view.votingEligibilityConfirmed &&
                          view.votingEligibilityErrorMessage != null;
                      return _ReviewAnswersButton(
                        key: const ValueKey('voting_review_answers_button'),
                        enabled:
                            canRetryEligibility ||
                            isIneligible ||
                            view.votingEligibilityConfirmed &&
                                !view.draft.isEmpty,
                        label: canRetryEligibility
                            ? 'Retry eligibility'
                            : isIneligible
                            ? 'Not eligible'
                            : 'Review answers',
                        onPressed: _handleBottomActionPressed,
                      );
                    }
                    final proposal = view.proposals[index - 1];
                    final isIneligible =
                        !view.votingEligibilityConfirmed &&
                        view.votingEligibilityErrorMessage != null;
                    return VotingProposalCard(
                      proposal: proposal,
                      selectedChoice: view.votingEligibilityConfirmed
                          ? view.draft.choices[proposal.id]
                          : null,
                      enabled: view.votingEligibilityConfirmed,
                      onDisabledOptionTap: isIneligible
                          ? _showIneligibleDialog
                          : null,
                      onChoice: (choice) => view.onChoice(proposal.id, choice),
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

class _ReviewAnswersButton extends StatelessWidget {
  const _ReviewAnswersButton({
    super.key,
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
  const _VotedPollContent({required this.view});

  final VotingDetailVoted view;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPaneToolbar(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: VotingVotedPollHeader(
                title: view.roundTitle,
                snapshotHeight: view.snapshotHeight,
                description: view.description,
                forumUri: view.forumUri,
                votingPowerZatoshi: view.votingPowerZatoshi,
                votingPowerPreparing: view.votingPowerPreparing,
                votedAt: view.votedAt,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: view.proposals.isEmpty
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
                  itemCount: view.proposals.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s),
                  itemBuilder: (context, index) {
                    final proposal = view.proposals[index];
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
        ),
      ],
    );
  }
}

class _PendingVoteContent extends StatelessWidget {
  const _PendingVoteContent({required this.view});

  final VotingDetailPendingVote view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPaneToolbar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              child: VotingForumLinkButton(
                                uri: view.forumUri!,
                              ),
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
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
