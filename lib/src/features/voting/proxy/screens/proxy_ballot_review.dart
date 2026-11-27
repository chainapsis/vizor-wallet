import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/voting/voting_session_provider.dart';
import '../../../../providers/voting/voting_submission_job_provider.dart';
import '../../voting_flow_models.dart';
import '../proxy_delegation_presentation.dart';
import '../proxy_delegation_providers.dart';
import '../proxy_delegation_repository.dart';
import '../widgets/proxy_delegate_widgets.dart';

/// Whether the round screen's drafted delegation may be submitted now, and
/// what the vote review shows about it.
@immutable
class ProxyDelegationReadiness {
  /// Creates the view.
  const ProxyDelegationReadiness({
    required this.round,
    required this.draft,
    required this.preview,
    required this.checks,
    required this.now,
  });

  /// Round facts, once loaded.
  final AsyncValue<ProxyRoundContext> round;

  /// The drafted split.
  final ProxyAllocationDraft draft;

  /// The planner's exact split, once previewed.
  final ProxyAllocationPreview? preview;

  /// The pre-proving registry check: one result per delegate.
  final AsyncValue<List<ApiConfirmedDelegate>> checks;

  /// Current time.
  final DateTime now;

  /// The vote end the review shows, as ordinary votes read it.
  DateTime? get voteEnd => round.value?.voteEndTime;

  /// Whether voting ended, which closes delegation too.
  bool get closed {
    final voteEnd = this.voteEnd;
    return voteEnd != null &&
        proxyDelegationWindowAt(now: now, voteEnd: voteEnd) ==
            ProxyDelegationWindow.closed;
  }

  /// Whether a commit may go ahead once the finality box is ticked.
  bool get ready =>
      draft.issue == null &&
      preview != null &&
      proxyChecksAllowCommit(checks.value) &&
      !closed;
}

/// Watches what the review needs to know about [key]'s drafted delegation.
ProxyDelegationReadiness watchProxyDelegationReadiness(
  WidgetRef ref,
  VotingSessionKey key,
) {
  return ProxyDelegationReadiness(
    round: ref.watch(proxyRoundContextProvider(key)),
    draft: ref.watch(proxyAllocationDraftProvider(key)),
    preview: ref.watch(proxyAllocationPreviewProvider(key)).value,
    checks: ref.watch(proxyDelegateChecksProvider(key)),
    now: ref.watch(proxyClockProvider)(),
  );
}

/// Whether the pre-proving check results let a commit go ahead: loaded, and
/// every verdict ok.
bool proxyChecksAllowCommit(List<ApiConfirmedDelegate>? checks) =>
    checks != null &&
    checks.every((delegate) => delegate.check == DelegateCheck.ok);

/// The vote review's delegation section: each delegate with its exact
/// weight and check, the kept share, the timing, and what delegating means.
/// The wallet's own answers follow it on the review.
class ProxyReviewDelegation extends StatelessWidget {
  /// Creates the section.
  const ProxyReviewDelegation({
    required this.readiness,
    this.onRetryChecks,
    this.onRetryRound,
    super.key,
  });

  /// What the review knows about the drafted delegation.
  final ProxyDelegationReadiness readiness;

  /// Runs the pre-proving check again.
  final VoidCallback? onRetryChecks;

  /// Loads the round facts again.
  final VoidCallback? onRetryRound;

  @override
  Widget build(BuildContext context) {
    final round = readiness.round;
    final roundValue = round.value;
    if (roundValue == null) {
      return round.hasError
          ? ProxyNotice(
              message: proxyErrorCopy(context.l10n, round.error!),
              tone: ProxyNoticeTone.error,
              actionLabel: context.l10n.commonTryAgain,
              onAction: onRetryRound,
            )
          : const SizedBox.shrink();
    }
    final colors = context.colors;
    final preview = readiness.preview;
    final checks = readiness.checks;
    final confirmed = checks.value;
    final checkError = checks.hasError ? checks.error : null;
    final cannotVerify =
        (checkError is ProxyDelegationError &&
            checkError.kind == ProxyDelegationErrorKind.cannotVerify) ||
        (confirmed?.any(
              (delegate) => delegate.check == DelegateCheck.cannotVerify,
            ) ??
            false);
    final draft = readiness.draft;
    final issue = draft.issue;
    final kept = preview != null && preview.keptBallots > BigInt.zero;
    const gap = SizedBox(height: AppSpacing.s);
    final titleStyle = AppTypography.bodyMediumStrong.copyWith(
      color: colors.text.accent,
    );
    return Column(
      key: const ValueKey('proxy_review_delegation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.proxyReviewDelegatesTitle, style: titleStyle),
        const SizedBox(height: AppSpacing.xs),
        ProxyDelegationTimingNotice(
          now: readiness.now,
          voteEnd: readiness.voteEnd ?? roundValue.voteEndTime,
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final (i, delegate) in draft.delegates.indexed) ...[
          ProxyReviewDelegateRow(
            delegate: delegate,
            ballots: preview?.delegations
                .where((d) => d.delegateIndex == delegate.entry.index)
                .firstOrNull
                ?.ballots,
            confirmed: confirmed != null && i < confirmed.length
                ? confirmed[i]
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (kept)
          ProxyCard(
            key: const ValueKey('proxy_review_kept'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.proxyKeepForMyselfLabel,
                    style: titleStyle,
                  ),
                ),
                Text(
                  formatProxyBallots(preview.keptBallots),
                  style: titleStyle,
                ),
              ],
            ),
          ),
        if (issue != null) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('proxy_review_issue'),
            message: proxyDraftIssueCopy(context.l10n, issue),
            tone: ProxyNoticeTone.error,
          ),
        ],
        if (checks.isLoading) ...[
          gap,
          ProxyNotice(message: context.l10n.proxyCheckingDelegates),
        ],
        if (cannotVerify) ...[
          gap,
          ProxyNotice(
            key: const ValueKey('proxy_review_cannot_verify'),
            message: context.l10n.proxyCannotVerify,
            tone: ProxyNoticeTone.error,
            actionLabel: context.l10n.commonTryAgain,
            onAction: onRetryChecks,
          ),
        ] else if (checkError != null) ...[
          gap,
          ProxyNotice(
            message: proxyErrorCopy(context.l10n, checkError),
            tone: ProxyNoticeTone.error,
            actionLabel: context.l10n.commonTryAgain,
            onAction: onRetryChecks,
          ),
        ],
      ],
    );
  }
}

/// What delegating means, under the review's answers.
class ProxyBeforeYouDelegate extends StatelessWidget {
  /// Creates the section.
  const ProxyBeforeYouDelegate({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('proxy_review_before_you_delegate'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.proxyBeforeYouDelegateTitle,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        ProxyBodyText(context.l10n.proxyIntro),
        const SizedBox(height: AppSpacing.xs),
        ProxyBodyText(context.l10n.proxyPrivacy),
        const SizedBox(height: AppSpacing.xs),
        ProxyBodyText(context.l10n.proxyHelperTiming),
        const SizedBox(height: AppSpacing.xs),
        ProxyBodyText(context.l10n.proxyKeepInstalled),
      ],
    );
  }
}

/// The review's pinned footer when the ballot carries a delegation: the
/// finality checkbox and its "Counts only with a ballot" line directly above
/// the submit [button]. The checkbox and the button never scroll; on a pane
/// too short for everything, the lines under the checkbox scroll inside the
/// footer instead. While the box is unticked, the first of them points there
/// from the disabled button.
class ProxyConfirmFooter extends StatelessWidget {
  /// Creates the footer.
  const ProxyConfirmFooter({
    required this.acknowledged,
    required this.onAcknowledgedChanged,
    required this.button,
    this.error,
    super.key,
  });

  /// Whether the finality checkbox is ticked.
  final bool acknowledged;

  /// The finality checkbox changed.
  final ValueChanged<bool> onAcknowledgedChanged;

  /// The submit button.
  final Widget button;

  /// A commit failure to show.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final colors = context.colors;
    return Column(
      key: const ValueKey('proxy_confirm_footer'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FinalityCheckbox(
          value: acknowledged,
          onChanged: onAcknowledgedChanged,
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!acknowledged)
                  Padding(
                    key: const ValueKey('proxy_confirm_checkbox_hint'),
                    padding: const EdgeInsets.only(left: 48),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_upward,
                          size: 16,
                          color: colors.text.secondary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            context.l10n.proxyConfirmCheckboxHint,
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xxs),
                Padding(
                  key: const ValueKey('proxy_counts_only_with_ballot'),
                  padding: const EdgeInsets.only(left: 48),
                  child: ProxyBodyText(context.l10n.proxyCountsOnlyWithBallot),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          ProxyNotice(
            key: const ValueKey('proxy_confirm_error'),
            message: error,
            tone: ProxyNoticeTone.error,
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        button,
      ],
    );
  }
}

/// One delegate on the review: identity, exact weight and share, and what
/// the pre-proving check said. Once the check ran, the row shows the
/// delegate as the chain proved it, lookalike warning included
/// (contracts-v1 §11.11).
class ProxyReviewDelegateRow extends StatelessWidget {
  /// Creates the row.
  const ProxyReviewDelegateRow({
    required this.delegate,
    required this.ballots,
    required this.confirmed,
    super.key,
  });

  /// The drafted delegate.
  final ProxyDraftDelegate delegate;

  /// Its planned weight, once previewed.
  final BigInt? ballots;

  /// Its pre-proving check, once run.
  final ApiConfirmedDelegate? confirmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final drafted = delegate.entry;
    final entry = confirmed?.listing ?? drafted;
    final ballots = this.ballots;
    final block = switch (confirmed?.check) {
      final check? => proxyCheckBlockCopy(
        context.l10n,
        proxyListingName(drafted),
        check,
      ),
      null => null,
    };
    final lookalike = entry.lookalikeOf;
    return ProxyCard(
      key: ValueKey('proxy_review_row_${entry.index}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProxyDelegateSummary(
            entry: entry,
            identiconSize: 32,
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  ballots == null ? '' : formatProxyBallots(ballots),
                  key: ValueKey('proxy_review_amount_${entry.index}'),
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  formatProxyPercent(delegate.percentBps ?? 0),
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (lookalike != null) ...[
            const SizedBox(height: AppSpacing.xs),
            ProxyNotice(
              message: context.l10n.proxyLookalike(lookalike),
              tone: ProxyNoticeTone.warning,
            ),
          ],
          if (block != null) ...[
            const SizedBox(height: AppSpacing.xs),
            ProxyNotice(
              key: ValueKey('proxy_review_refused_${entry.index}'),
              message: block,
              tone: ProxyNoticeTone.error,
            ),
          ],
        ],
      ),
    );
  }
}

class _FinalityCheckbox extends StatelessWidget {
  const _FinalityCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: GestureDetector(
        key: const ValueKey('proxy_finality_checkbox'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            Material(
              type: MaterialType.transparency,
              child: Checkbox(
                value: value,
                onChanged: (checked) => onChanged(checked ?? false),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                context.l10n.proxyFinality,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Commits [key]'s drafted delegation and starts the job that carries the
/// ballot, all for [key]'s account, the one the review confirmed, whichever
/// account is active meanwhile. A delegation that keeps a share carries
/// the kept share's [answers] (choices, every other one of [proposalIds]
/// skipped): they are recorded first, because zcash_voting refuses a
/// commit that keeps ballots without them, and the vote job then sends the
/// delegation and the casts right after it. One that delegates everything
/// has no [answers] and starts the proxy job; answers the delegates
/// override are dropped.
///
/// Availability is checked again right before the commit, so a pause fails
/// here with nothing recorded, and a refused commit clears the answers it
/// recorded. A commit whose own check stops a delegate refreshes the
/// review's check, which shows why. Returns why nothing was sent, or null.
/// [container] outlives the review, which may close meanwhile.
Future<String?> submitProxyBallot(
  AppLocalizations l10n,
  ProviderContainer container, {
  required VotingSessionKey key,
  required List<VotingDraftVote> answers,
  required List<int> proposalIds,
}) async {
  final roundId = key.roundId;
  final preview = container.read(proxyAllocationPreviewProvider(key)).value;
  if (preview == null) return l10n.proxyCommitError;
  final request = container
      .read(proxyAllocationDraftProvider(key))
      .toRequest(roundId);
  // Held until the job starts, as the review may close meanwhile.
  final held = [
    container.listen(proxyDelegationRepositoryProvider(key), (_, _) {}),
    container.listen(votingSubmissionSessionProvider(key), (_, _) {}),
  ];
  try {
    final repository = container.read(proxyDelegationRepositoryProvider(key));
    final session = container.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    var answersRecorded = false;
    try {
      final block = proxyAvailabilityBlockCopy(
        l10n,
        await repository.availability(roundId),
      );
      if (block != null) return block;
      if (answers.isNotEmpty) {
        await session.recordBallotIntents(
          draftVotes: answers,
          allProposalIds: proposalIds,
        );
        answersRecorded = true;
      }
      await repository.commit(request, confirmed: preview);
    } catch (error) {
      if (answersRecorded) {
        try {
          await session.clearBallotIntents(proposalIds);
        } catch (clearError) {
          debugPrint(
            '[zcash] Voting: kept share answers cleanup failed: $clearError',
          );
        }
      }
      switch (error) {
        case ProxyDelegationError(kind: ProxyDelegationErrorKind.planChanged):
          container.invalidate(proxyAllocationPreviewProvider(key));
        case ProxyReviewChangedException() ||
            ProxyDelegationError(kind: ProxyDelegationErrorKind.cannotVerify):
          container.invalidate(proxyDelegateChecksProvider(key));
      }
      return proxyErrorCopy(l10n, error, fallback: l10n.proxyCommitError);
    }
    container.read(proxyAllocationDraftProvider(key).notifier).clear();
    container.invalidate(proxyAllocationStatusProvider(key));
    container.invalidate(proxyAvailabilityProvider(key));
    final jobs = container.read(votingSubmissionJobsProvider.notifier);
    if (answers.isNotEmpty) {
      await jobs.start(roundId, accountUuid: key.accountUuid);
      return null;
    }
    try {
      await container.read(votingDraftProvider(key).notifier).clearAll();
    } catch (error) {
      debugPrint(
        '[zcash] Voting: delegated ballot draft cleanup failed: $error',
      );
    }
    await jobs.startProxy(roundId, accountUuid: key.accountUuid);
    return null;
  } finally {
    for (final subscription in held) {
      subscription.close();
    }
  }
}
