import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/proxy_delegation_feature_config.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../voting_flow_models.dart';
import '../proxy_delegation_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../proxy_delegation_routes.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// The round screen's delegation line: the wallet's voting power, and a way
/// to let delegates answer some or all of the ballot. Renders nothing when
/// the dormant flag is off or the round is not a proxy round for this
/// wallet.
class ProxyVotingPowerLine extends ConsumerWidget {
  /// Creates the line for [roundId].
  const ProxyVotingPowerLine({required this.roundId, super.key});

  /// Round whose questions the line sits above.
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
      eligibleBallots: ref
          .watch(proxyRoundContextProvider(key))
          .value
          ?.eligibleBallots,
      delegation: ref.watch(proxyBallotDelegationProvider(key)),
      onLetDelegateVote: () =>
          context.push(proxyDelegateDirectoryRoute(roundId)),
      onRemove: () =>
          ref.read(proxyAllocationDraftProvider(key).notifier).clear(),
      onRetry: () {
        ref.invalidate(proxyAvailabilityProvider(key));
        ref.invalidate(proxyRoundContextProvider(key));
      },
    );
  }
}

/// Session-free round screen line shared by the live widget and tests.
class ProxyVotingPowerLineContent extends StatelessWidget {
  /// Creates the content.
  const ProxyVotingPowerLineContent({
    required this.kind,
    this.eligibleBallots,
    this.delegation,
    this.onLetDelegateVote,
    this.onRemove,
    this.onRetry,
    super.key,
  });

  /// What the round allows.
  final ProxyEntryKind kind;

  /// Voting power the wallet can allocate, in ballots, once known.
  final BigInt? eligibleBallots;

  /// The delegation the ballot carries, drafted or committed.
  final ProxyBallotDelegation? delegation;

  /// Opens delegate choice, to choose or change delegates.
  final VoidCallback? onLetDelegateVote;

  /// Drops the drafted delegation.
  final VoidCallback? onRemove;

  /// Retries a failed check.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (kind == ProxyEntryKind.hidden) return const SizedBox.shrink();
    final power = _votingPower();
    final body = _body(context);
    return ProxyCard(
      key: const ValueKey('proxy_voting_power_line'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (power != null)
            ProxyBodyText(
              context.l10n.proxyVotingPower(formatProxyBallots(power)),
              strong: true,
            ),
          if (power != null && body.isNotEmpty)
            const SizedBox(height: AppSpacing.xs),
          ...body,
        ],
      ),
    );
  }

  /// The wallet's whole voting power: the committed split's parts, or what
  /// the round still lets it allocate. None once the wallet voted or the
  /// round ended, which the reason line says instead.
  BigInt? _votingPower() {
    final delegation = this.delegation;
    if (delegation == null &&
        (kind == ProxyEntryKind.alreadyVoted ||
            kind == ProxyEntryKind.usedElsewhere ||
            kind == ProxyEntryKind.voteEnded)) {
      return null;
    }
    if (delegation != null && delegation.committed) {
      return delegation.delegates.fold<BigInt>(
        delegation.keptBallots ?? BigInt.zero,
        (sum, delegate) => sum + (delegate.ballots ?? BigInt.zero),
      );
    }
    return eligibleBallots;
  }

  /// What follows the voting power for [kind].
  List<Widget> _body(BuildContext context) {
    final delegation = this.delegation;
    if (delegation != null) return _split(context, delegation);
    switch (kind) {
      case ProxyEntryKind.available:
        return [
          AppButton(
            key: const ValueKey('proxy_let_delegate_vote'),
            onPressed: onLetDelegateVote,
            variant: AppButtonVariant.secondary,
            expand: true,
            growWithContent: true,
            constrainContent: true,
            child: Text(context.l10n.proxyLetDelegateVoteLabel),
          ),
        ];
      // A committed allocation always names a delegate, so it shows its
      // split above.
      case ProxyEntryKind.locked || ProxyEntryKind.hidden:
        return const [];
      case ProxyEntryKind.timingUnavailable || ProxyEntryKind.cannotVerify:
        return [
          ProxyNotice(
            key: ValueKey('proxy_line_${kind.name}'),
            message: kind == ProxyEntryKind.cannotVerify
                ? context.l10n.proxyCannotVerify
                : context.l10n.proxyTimingUnavailable,
            tone: ProxyNoticeTone.warning,
            actionLabel: context.l10n.commonTryAgain,
            onAction: onRetry,
          ),
        ];
      case ProxyEntryKind.paused ||
          ProxyEntryKind.alreadyVoted ||
          ProxyEntryKind.usedElsewhere ||
          ProxyEntryKind.voteEnded:
        return [
          Text(
            switch (kind) {
              ProxyEntryKind.paused => context.l10n.proxyPaused,
              ProxyEntryKind.alreadyVoted => context.l10n.proxyAlreadyVoted,
              ProxyEntryKind.usedElsewhere => context.l10n.proxyUsedElsewhere,
              _ => context.l10n.proxyTooLate,
            },
            key: ValueKey('proxy_line_${kind.name}'),
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ];
    }
  }

  /// The split line, and for a draft its issue and the ways to change it.
  List<Widget> _split(BuildContext context, ProxyBallotDelegation delegation) {
    final issue = delegation.issue;
    return [
      ProxyBodyText(
        proxyBallotSplitText(context.l10n, delegation),
        key: const ValueKey('proxy_line_split'),
      ),
      if (issue != null) ...[
        const SizedBox(height: AppSpacing.xs),
        ProxyNotice(
          key: const ValueKey('proxy_line_issue'),
          message: proxyDraftIssueCopy(context.l10n, issue),
          tone: ProxyNoticeTone.warning,
        ),
      ],
      if (!delegation.committed) ...[
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton(
              key: const ValueKey('proxy_line_change'),
              onPressed: onLetDelegateVote,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              child: Text(context.l10n.proxyChangeDelegationLabel),
            ),
            AppButton(
              key: const ValueKey('proxy_line_remove'),
              onPressed: onRemove,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              child: Text(context.l10n.commonRemove),
            ),
          ],
        ),
      ],
    ];
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
