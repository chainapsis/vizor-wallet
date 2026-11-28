import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/proxy_delegation_feature_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../voting_flow_models.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// The round screen's delegation card: a way into choosing delegates, the
/// drafted or committed split once there is one, or why delegating isn't
/// open. Renders nothing when the dormant flag is off or the round is not a
/// proxy round for this wallet.
class ProxyVotingPowerLine extends ConsumerWidget {
  /// Creates the card for [roundId].
  const ProxyVotingPowerLine({required this.roundId, super.key});

  /// Round whose questions the card sits above.
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ref.watch(proxyActiveSessionKeyProvider(roundId));
    if (key == null) return const SizedBox.shrink();
    final kind = ref.watch(proxyEntryKindProvider(key)).value;
    if (kind == null || kind == ProxyEntryKind.hidden) {
      return const SizedBox.shrink();
    }
    return ProxyVotingPowerLineContent(
      kind: kind,
      delegation: ref.watch(proxyBallotDelegationProvider(key)),
      onChoose: () => context.push(proxyDelegateDirectoryRoute(roundId)),
      // Under the split sits delegate choice, as when the draft was made,
      // so the split's Add delegate goes back to it.
      onEdit: () {
        context.push(proxyDelegateDirectoryRoute(roundId));
        context.push(proxyAllocationRoute(roundId));
      },
      onRetry: () {
        ref.invalidate(proxyAvailabilityProvider(key));
        ref.invalidate(proxyRoundContextProvider(key));
      },
    );
  }
}

/// Session-free round screen card shared by the live widget and tests.
class ProxyVotingPowerLineContent extends StatelessWidget {
  /// Creates the content.
  const ProxyVotingPowerLineContent({
    required this.kind,
    this.delegation,
    this.onChoose,
    this.onEdit,
    this.onRetry,
    super.key,
  });

  /// What the round allows.
  final ProxyEntryKind kind;

  /// The delegation the ballot carries, drafted or committed.
  final ProxyBallotDelegation? delegation;

  /// Opens delegate choice.
  final VoidCallback? onChoose;

  /// Opens the drafted split to change it.
  final VoidCallback? onEdit;

  /// Retries a failed check.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (kind == ProxyEntryKind.hidden) return const SizedBox.shrink();
    final l10n = context.l10n;
    final delegation = this.delegation;
    if (delegation != null) {
      final issue = delegation.issue;
      return _DelegationCard(
        key: const ValueKey('proxy_voting_power_line'),
        tapKey: const ValueKey('proxy_line_edit'),
        title: proxyDelegationTitle(l10n, delegation),
        body: proxyDelegationSplitText(l10n, delegation),
        notice: issue == null
            ? null
            : ProxyNotice(
                key: const ValueKey('proxy_line_issue'),
                message: proxyDraftIssueCopy(l10n, issue),
                tone: ProxyNoticeTone.warning,
              ),
        // A committed delegation is final.
        onTap: delegation.committed ? null : onEdit,
      );
    }
    if (kind == ProxyEntryKind.available) {
      return _DelegationCard(
        key: const ValueKey('proxy_voting_power_line'),
        tapKey: const ValueKey('proxy_let_delegate_vote'),
        title: l10n.proxyDelegateVoteTitle,
        body: l10n.proxyDelegateVoteBody,
        onTap: onChoose,
      );
    }
    return ProxyCard(
      key: const ValueKey('proxy_voting_power_line'),
      child: switch (kind) {
        ProxyEntryKind.timingUnavailable ||
        ProxyEntryKind.cannotVerify => ProxyNotice(
          key: ValueKey('proxy_line_${kind.name}'),
          message: kind == ProxyEntryKind.cannotVerify
              ? l10n.proxyCannotVerify
              : l10n.proxyTimingUnavailable,
          tone: ProxyNoticeTone.warning,
          actionLabel: l10n.commonTryAgain,
          onAction: onRetry,
        ),
        _ => Text(
          switch (kind) {
            ProxyEntryKind.paused => l10n.proxyPaused,
            ProxyEntryKind.alreadyVoted => l10n.proxyAlreadyVoted,
            ProxyEntryKind.usedElsewhere => l10n.proxyUsedElsewhere,
            _ => l10n.proxyTooLate,
          },
          key: ValueKey('proxy_line_${kind.name}'),
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      },
    );
  }
}

/// The card's title and line, an optional notice under them, and, when it
/// opens something, a chevron and the whole card as the button.
class _DelegationCard extends StatelessWidget {
  const _DelegationCard({
    required this.title,
    required this.tapKey,
    this.body,
    this.notice,
    this.onTap,
    super.key,
  });

  final String title;
  final Key tapKey;
  final String? body;
  final Widget? notice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = this.body;
    final notice = this.notice;
    final onTap = this.onTap;
    final card = ProxyCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    body,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
                if (notice != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  notice,
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.s),
            AppIcon(AppIcons.chevronForward, color: colors.icon.muted),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: tapKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}

/// Under a question the delegates answer for the wallet: who answers it.
class ProxyAnswersForYou extends StatelessWidget {
  /// Creates the line for [names].
  const ProxyAnswersForYou({required this.names, super.key});

  /// The delegates answering, from `proxyDelegateName`.
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.proxyAnswersForYou(
        proxyNamesPhrase(context.l10n, names),
        names.length,
      ),
      style: AppTypography.bodyMedium.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

/// Under a question in the round's status: the wallet's own answer with its
/// amount, then each delegate's (see [proxyQuestionLines]).
class ProxyQuestionStatus extends StatelessWidget {
  /// Creates the lines for [proposal].
  const ProxyQuestionStatus({
    required this.proposal,
    required this.ownChoice,
    required this.status,
    super.key,
  });

  /// The question.
  final VotingProposalView proposal;

  /// The wallet's own choice, when it answered.
  final int? ownChoice;

  /// The committed allocation with its delegates' ballots.
  final ApiProxyAllocationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lines = proxyQuestionLines(
      context.l10n,
      proposal: proposal,
      ownChoice: ownChoice,
      status: status,
    );
    return Column(
      key: ValueKey('proxy_question_status_${proposal.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${line.who} · ${line.amount}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    line.answer,
                    textAlign: TextAlign.end,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The round status's delegation summary: each delegation with its weight
/// and stage, and while voting runs, that it counts only with a ballot.
class ProxyDelegationSummary extends StatelessWidget {
  /// Creates the summary.
  const ProxyDelegationSummary({
    required this.status,
    required this.roundActive,
    super.key,
  });

  /// The committed allocation.
  final ApiProxyAllocationStatus status;

  /// `now < vote_end`.
  final bool roundActive;

  @override
  Widget build(BuildContext context) {
    return ProxyCard(
      key: const ValueKey('proxy_delegation_summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProxyBodyText(context.l10n.proxyYourDelegationTitle, strong: true),
          for (final view in status.delegations) ...[
            const SizedBox(height: AppSpacing.xxs),
            ProxyBodyText(
              proxyDelegationLine(context.l10n, view),
              key: ValueKey('proxy_summary_delegation_${view.delegateIndex}'),
            ),
            if (view.stage == ProxyDelegationStage.notCounted)
              ProxyBodyText(context.l10n.proxyNotCounted)
            else if (view.ballot.kind == ApiDelegateBallotKind.notCounted)
              ProxyBodyText(context.l10n.proxyNoBallot(proxyViewName(view))),
          ],
          if (roundActive) ...[
            const SizedBox(height: AppSpacing.xs),
            ProxyBodyText(context.l10n.proxyCountsOnlyWithBallot),
          ],
        ],
      ),
    );
  }
}

/// The active account's delegation in [roundId], from the committed
/// allocation. Null with the dormant flag off or without a committed
/// allocation, so the caller can leave the status as it was.
ApiProxyAllocationStatus? watchProxyRoundStatus(WidgetRef ref, String roundId) {
  if (!ref.watch(proxyDelegationFeatureEnabledProvider)) return null;
  final key = ref.watch(proxyActiveSessionKeyProvider(roundId));
  if (key == null) return null;
  return ref.watch(proxyAllocationStatusProvider(key)).value;
}

/// PD-8 addition to the results screen: these totals include the ZEC the
/// wallet delegated. It names no delegate and splits no totals.
class ProxyResultsDelegationNote extends ConsumerWidget {
  /// Creates the note for [roundId].
  const ProxyResultsDelegationNote({required this.roundId, super.key});

  /// Round whose results are shown.
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = watchProxyRoundStatus(ref, roundId);
    if (status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s),
      child: ProxyNotice(
        key: const ValueKey('proxy_results_delegation_note'),
        message: context.l10n.proxyResultsNote,
      ),
    );
  }
}
