import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/navigation/app_back_resolver.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_tree_sync_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_flow_models.dart';
import '../voting_formatters.dart';
import '../voting_resume_plan.dart';
import '../voting_routes.dart';

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

  @override
  void didUpdateWidget(covariant VotingProposalDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId != widget.roundId) {
      _votingPowerPreparationStarted = false;
      _votingPowerPreparationInFlight = false;
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              _Message(title: "Couldn't load poll", message: '$error'),
          data: (state) {
            final round = state.round;
            if (round == null) {
              return const _Message(
                title: 'Poll unavailable',
                message: 'The selected poll could not be loaded.',
              );
            }
            if (shouldPreSyncVotingTree(round.status)) {
              unawaited(
                ref.read(votingTreePreSyncProvider).preSyncRound(round.roundId),
              );
            }
            final accountUuid = state.accountUuid;
            final draftKey = accountUuid == null
                ? null
                : VotingSessionKey(roundId: roundId, accountUuid: accountUuid);
            final draft = draftKey == null
                ? const VotingDraftState()
                : ref.watch(votingDraftProvider(draftKey));
            final proposals = proposalsFromRound(round);
            final completedVote = _CompletedVote.fromPlan(
              state.resumePlan,
              proposals,
            );
            _maybePrepareVotingPower(state);
            if (completedVote != null) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _VotedPollContent(
                  roundTitle: round.title.isEmpty
                      ? 'Coinholder Poll'
                      : round.title,
                  snapshotHeight: round.snapshotHeight,
                  description: _roundDescription(round.rawJson),
                  votingPowerZatoshi: state.eligibleWeightZatoshi,
                  votingPowerPreparing: _votingPowerPreparationInFlight,
                  votedAt: completedVote.votedAt,
                  proposals: proposals,
                  choicesByProposalId: completedVote.choicesByProposalId,
                ),
              );
            }
            final pendingVote = _PendingVoteRecovery.fromPlan(state.resumePlan);
            if (pendingVote != null) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _PendingVoteContent(
                  roundTitle: round.title.isEmpty
                      ? 'Coinholder Poll'
                      : round.title,
                  snapshotHeight: round.snapshotHeight,
                  description: _roundDescription(round.rawJson),
                  recovery: pendingVote,
                ),
              );
            }
            return _ActivePollContent(
              roundId: roundId,
              title: round.title.isEmpty ? 'Coinholder Poll' : round.title,
              snapshotHeight: round.snapshotHeight,
              description: _roundDescription(round.rawJson),
              endDate: _roundEndDate(round.rawJson),
              votingPowerZatoshi: state.eligibleWeightZatoshi,
              votingPowerPreparing: _votingPowerPreparationInFlight,
              proposals: proposals,
              draft: draft,
              onChoice: draftKey == null
                  ? (_, _) {}
                  : (proposalId, choice) {
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

  void _maybePrepareVotingPower(VotingSessionState state) {
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
            .prepareDelegation()
            .whenComplete(() {
              if (!mounted) return;
              setState(() {
                _votingPowerPreparationInFlight = false;
              });
            }),
      );
    });
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

class _VotingTopBar extends StatelessWidget {
  const _VotingTopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(left: AppSpacing.md, child: _VotingBackButton()),
          Text(
            'COINHOLDER POLLING',
            textAlign: TextAlign.center,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.18,
            ),
          ),
        ],
      ),
    );
  }
}

class _VotingBackButton extends StatefulWidget {
  const _VotingBackButton();

  @override
  State<_VotingBackButton> createState() => _VotingBackButtonState();
}

class _VotingBackButtonState extends State<_VotingBackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final target = AppBackResolver.resolve(context);
    return Semantics(
      button: true,
      label: 'Back to ${target.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => target.navigate(context),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hovered ? colors.state.hover : null,
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Center(
              child: AppIcon(
                AppIcons.arrowBack,
                size: 20,
                color: colors.icon.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }
}

class _ActivePollContent extends StatefulWidget {
  const _ActivePollContent({
    required this.roundId,
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.endDate,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.proposals,
    required this.draft,
    required this.onChoice,
  });

  final String roundId;
  final String title;
  final int snapshotHeight;
  final String description;
  final DateTime? endDate;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final List<VotingProposalView> proposals;
  final VotingDraftState draft;
  final void Function(int proposalId, int? choice) onChoice;

  @override
  State<_ActivePollContent> createState() => _ActivePollContentState();
}

class _ActivePollContentState extends State<_ActivePollContent> {
  bool _descriptionExpanded = false;

  Future<void> _handleBottomActionPressed() async {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _VotingTopBar(),
        Expanded(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: widget.proposals.isEmpty
                      ? const _Message(
                          title: 'No proposals',
                          message: 'This poll does not contain any proposals.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.sm,
                            AppSpacing.md,
                            120,
                          ),
                          itemCount: widget.proposals.length + 1,
                          separatorBuilder: (_, index) => SizedBox(
                            height: index == 0 ? AppSpacing.md : AppSpacing.xs,
                          ),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _PollSummary(
                                title: widget.title,
                                snapshotHeight: widget.snapshotHeight,
                                description: widget.description,
                                endDate: widget.endDate,
                                votingPowerZatoshi: widget.votingPowerZatoshi,
                                votingPowerPreparing:
                                    widget.votingPowerPreparing,
                                expanded: _descriptionExpanded,
                                onToggleDescription: () => setState(() {
                                  _descriptionExpanded = !_descriptionExpanded;
                                }),
                              );
                            }
                            final proposal = widget.proposals[index - 1];
                            return _ProposalCard(
                              proposal: proposal,
                              selectedChoice: widget.draft.choices[proposal.id],
                              onChoice: (choice) =>
                                  widget.onChoice(proposal.id, choice),
                            );
                          },
                        ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomActionBar(
                  label: 'Review Answers',
                  enabled: !widget.draft.isEmpty,
                  onPressed: _handleBottomActionPressed,
                ),
              ),
            ],
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
                child: const Text('Continue to Review'),
              ),
              const SizedBox(height: AppSpacing.s),
              AppButton(
                onPressed: () => Navigator.of(context).pop(false),
                variant: AppButtonVariant.ghost,
                minWidth: 312,
                child: const Text('Keep Voting'),
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
    required this.endDate,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.expanded,
    required this.onToggleDescription,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final DateTime? endDate;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final bool expanded;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasDescription = description.isNotEmpty;
    final descriptionStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
      height: 20 / 14,
      letterSpacing: -0.22,
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
                    letterSpacing: -0.32,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '#${_formatHeight(snapshotHeight)}',
                style: AppTypography.headlineMedium.copyWith(
                  color: colors.text.accent,
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  height: 30 / 20,
                  letterSpacing: -0.32,
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
                  : 'Ends ${_formatDate(endDate!)}',
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
        if (hasDescription) ...[
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              final canExpand = _textExceedsSingleLine(
                context: context,
                text: description,
                style: descriptionStyle,
                maxWidth: constraints.maxWidth,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    description,
                    maxLines: expanded || !canExpand ? null : 1,
                    overflow: expanded || !canExpand
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: descriptionStyle,
                  ),
                  if (canExpand)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _ViewMoreButton(
                        expanded: expanded,
                        onPressed: onToggleDescription,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

bool _textExceedsSingleLine({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double maxWidth,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return false;
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return textPainter.didExceedMaxLines;
}

class _ViewMoreButton extends StatelessWidget {
  const _ViewMoreButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'View less' : 'View more',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
                height: 20 / 14,
                letterSpacing: -0.22,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Transform.rotate(
              angle: expanded ? -1.5708 : 1.5708,
              child: AppIcon(
                AppIcons.chevronForward,
                size: 16,
                color: colors.icon.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.background.ground.withValues(alpha: 0),
            colors.background.ground,
            colors.background.ground,
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AppButton(
                    onPressed: enabled ? onPressed : null,
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.large,
                    minWidth: constraints.maxWidth,
                    child: Text(label),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VotedPollContent extends StatelessWidget {
  const _VotedPollContent({
    required this.roundTitle,
    required this.snapshotHeight,
    required this.description,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votedAt,
    required this.proposals,
    required this.choicesByProposalId,
  });

  final String roundTitle;
  final int snapshotHeight;
  final String description;
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
        const Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
        const SizedBox(height: AppSpacing.s),
        _VotedPollHeader(
          title: roundTitle,
          snapshotHeight: snapshotHeight,
          description: description,
          votingPowerZatoshi: votingPowerZatoshi,
          votingPowerPreparing: votingPowerPreparing,
          votedAt: votedAt,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: proposals.isEmpty
              ? const _Message(
                  title: 'No proposals',
                  message: 'This poll does not contain any proposals.',
                )
              : ListView.separated(
                  itemCount: proposals.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s),
                  itemBuilder: (context, index) {
                    final proposal = proposals[index];
                    return _VotedProposalCard(
                      proposal: proposal,
                      choice: choicesByProposalId[proposal.id],
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
    required this.recovery,
  });

  final String roundTitle;
  final int snapshotHeight;
  final String description;
  final _PendingVoteRecovery recovery;

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
                        '#${_formatHeight(snapshotHeight)}',
                        style: AppTypography.headlineSmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Vote still finalizing',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    recovery.message,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    onPressed: () => context.go('/voting'),
                    variant: AppButtonVariant.secondary,
                    child: const Text('Back to polls'),
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
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votedAt,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final DateTime? votedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.headlineMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${_formatHeight(snapshotHeight)}',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            _MetaText(
              votedAt == null ? 'Voted' : 'Voted ${_formatDate(votedAt!)}',
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
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
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
        letterSpacing: -0.07,
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
        return const _MetaText('Voting Power unavailable');
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
    return _MetaText('Voting Power ${formatVotingPower(votingPower)}');
  }
}

class _VotedProposalCard extends StatelessWidget {
  const _VotedProposalCard({required this.proposal, required this.choice});

  final VotingProposalView proposal;
  final int? choice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final choiceLabel = _choiceLabel(proposal, choice);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
        boxShadow: [
          BoxShadow(
            color: colors.background.neutralScrim.withValues(alpha: 0.12),
            offset: const Offset(0, 8),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProposalBadge('Proposal ${proposal.id}'),
              const Spacer(),
              _ChoiceBadge(choiceLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProposalBadge extends StatelessWidget {
  const _ProposalBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: colors.border.regular),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: colors.text.secondary,
          height: 16 / 12,
          letterSpacing: -0.07,
        ),
      ),
    );
  }
}

class _ChoiceBadge extends StatelessWidget {
  const _ChoiceBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _choicePalette(colors, label);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(color: palette.text),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.selectedChoice,
    required this.onChoice,
  });

  final VotingProposalView proposal;
  final int? selectedChoice;
  final ValueChanged<int?> onChoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badge = _proposalBadge(proposal);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A231F20),
            offset: Offset(0, 1),
            blurRadius: 1,
            spreadRadius: -0.5,
          ),
          BoxShadow(
            color: Color(0x0A231F20),
            offset: Offset(0, 3),
            blurRadius: 3,
            spreadRadius: -1.5,
          ),
          BoxShadow(
            color: Color(0x0A231F20),
            offset: Offset(0, 24),
            blurRadius: 24,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null) ...[
            _ProposalBadge(badge),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              letterSpacing: -0.26,
            ),
          ),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
                height: 16 / 12,
                letterSpacing: -0.07,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s),
          for (final option in proposal.options) ...[
            _OptionRow(
              option: option,
              selected: selectedChoice == option.index,
              onTap: () => onChoice(
                selectedChoice == option.index ? null : option.index,
              ),
            ),
            if (option != proposal.options.last)
              const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _CompletedVote {
  const _CompletedVote({
    required this.choicesByProposalId,
    required this.votedAt,
  });

  final Map<int, int?> choicesByProposalId;
  final DateTime? votedAt;

  static _CompletedVote? fromPlan(
    VotingResumePlan? plan,
    List<VotingProposalView> proposals,
  ) {
    if (plan == null ||
        _hasBlockingRecoveryWork(plan) ||
        !_hasCompletedVoteArtifact(plan)) {
      return null;
    }
    final choices = <int, int?>{};
    for (final proposal in proposals) {
      final proposalChoices = plan.votesByKey.values
          .where((vote) => vote.proposalId == proposal.id)
          .map((vote) => vote.choice)
          .toSet();
      choices[proposal.id] = proposalChoices.length == 1
          ? proposalChoices.single
          : null;
    }
    return _CompletedVote(
      choicesByProposalId: choices,
      votedAt: _submittedAtFromPlan(plan),
    );
  }
}

class _PendingVoteRecovery {
  const _PendingVoteRecovery({required this.message});

  final String message;

  static _PendingVoteRecovery? fromPlan(VotingResumePlan? plan) {
    if (plan == null ||
        !_hasBlockingRecoveryWork(plan) ||
        !_hasCompletedVoteArtifact(plan)) {
      return null;
    }
    if (plan.pendingDelegationBundleIndexes.isNotEmpty) {
      return const _PendingVoteRecovery(
        message:
            'This vote has local progress, but delegation is not fully confirmed yet. The app should continue recovery before accepting another vote.',
      );
    }
    if (plan.pendingVoteSubmissionKeys.isNotEmpty ||
        plan.incompleteVoteRecoveryKeys.isNotEmpty) {
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

bool _hasCompletedVoteArtifact(VotingResumePlan plan) {
  return plan.hasCompletedVoteArtifact;
}

bool _hasBlockingRecoveryWork(VotingResumePlan plan) {
  return plan.hasBlockingCompletedVoteDisplay;
}

class _ChoicePalette {
  const _ChoicePalette({
    required this.background,
    required this.border,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color text;
}

_ChoicePalette _choicePalette(AppColors colors, String label) {
  final lower = label.toLowerCase();
  if (lower.contains('support') || lower.contains('yes')) {
    return _ChoicePalette(
      background: colors.background.utilitySuccessSubtle,
      border: colors.background.utilitySuccessAlpha,
      text: colors.text.success,
    );
  }
  if (lower.contains('oppose') || lower.contains('no')) {
    return _ChoicePalette(
      background: colors.background.utilityDestructiveSubtle,
      border: colors.background.utilityDestructiveAlpha,
      text: colors.text.destructive,
    );
  }
  return _ChoicePalette(
    background: colors.background.neutralSubtleOpacity,
    border: colors.border.subtle,
    text: colors.text.secondary,
  );
}

String _choiceLabel(VotingProposalView proposal, int? choice) {
  if (choice == null) return 'Vote recorded';
  return proposal.options
      .firstWhere(
        (option) => option.index == choice,
        orElse: () => VotingOptionView(index: choice, label: 'Choice $choice'),
      )
      .label;
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
  return _dateFromJson(json, const [
    'end_date',
    'endDate',
    'ends_at',
    'endsAt',
    'close_date',
    'closeDate',
    'closes_at',
    'closesAt',
    'deadline',
    'voting_end',
    'votingEnd',
    'poll_end',
    'pollEnd',
    'vote_end_time',
    'voteEndTime',
  ]);
}

DateTime? _dateFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final date = _parseDate(json[key]);
    if (date != null) return date;
  }
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final milliseconds = value > 100000000000
        ? value.toInt()
        : (value * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  final text = value.toString().trim();
  final numeric = num.tryParse(text);
  if (numeric != null) return _parseDate(numeric);
  return DateTime.tryParse(text);
}

String _formatHeight(int height) {
  final text = height.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final remaining = text.length - i;
    buffer.write(text[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
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

String? _proposalBadge(VotingProposalView proposal) {
  final match = RegExp(
    r'\bZIP[-\s]?\d+\b',
    caseSensitive: false,
  ).firstMatch('${proposal.title} ${proposal.description}');
  if (match == null) return null;
  return match.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), '-');
}

DateTime? _submittedAtFromPlan(VotingResumePlan plan) {
  final timestamps = plan.shareDelegations
      .map((record) => record.createdAt)
      .where((value) => value > BigInt.zero)
      .toList();
  if (timestamps.isEmpty) return null;
  timestamps.sort();
  final raw = timestamps.last;
  final milliseconds = raw > BigInt.from(100000000000)
      ? raw.toInt()
      : (raw * BigInt.from(1000)).toInt();
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final VotingOptionView option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.small),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.background.brandCrimsonAlpha
              : colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(
            color: selected
                ? colors.border.brandCrimsonStrong
                : colors.border.subtle,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            Text(
              selected ? 'Selected' : 'Choose',
              style: AppTypography.bodySmall.copyWith(
                color: selected
                    ? colors.text.brandCrimson
                    : colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
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
