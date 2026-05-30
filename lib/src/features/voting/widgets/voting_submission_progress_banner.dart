import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/voting/voting_submission_job_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_routes.dart';

class VotingSubmissionProgressBanner extends ConsumerWidget {
  const VotingSubmissionProgressBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(votingSubmissionJobProvider);
    final key = job.key;
    if (key == null || !job.hasVisibleJob) {
      return const SizedBox.shrink();
    }

    final session = ref.watch(votingSubmissionJobSessionProvider);
    final sessionState = session?.value;
    final title = _titleFor(job.status);
    final accountName = _accountName(ref, key.accountUuid);
    final detail = _detailFor(job, sessionState, accountName);
    final progress = _progressFor(job, sessionState);
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.raised.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
          border: Border.all(color: colors.border.subtle),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              AppIcon(
                job.status == VotingSubmissionJobStatus.error
                    ? AppIcons.warning
                    : job.status == VotingSubmissionJobStatus.complete
                    ? AppIcons.checkCircle
                    : AppIcons.sync,
                size: 18,
                color: job.status == VotingSubmissionJobStatus.error
                    ? colors.icon.destructive
                    : colors.icon.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: AppTypography.bodySmall.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.full),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: progress,
                        backgroundColor: colors.border.subtle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              AppButton(
                onPressed: () {
                  final route = job.status == VotingSubmissionJobStatus.complete
                      ? votingSubmissionConfirmedRoute(key.roundId)
                      : votingStatusRoute(key.roundId);
                  context.go(route);
                },
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                child: const Text('View'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _accountName(WidgetRef ref, String accountUuid) {
    final accounts = ref.watch(accountProvider).value?.accounts;
    if (accounts == null) return 'this account';
    for (final account in accounts) {
      if (account.uuid == accountUuid) return account.name;
    }
    return 'this account';
  }

  String _titleFor(VotingSubmissionJobStatus status) {
    return switch (status) {
      VotingSubmissionJobStatus.idle => 'Vote submission',
      VotingSubmissionJobStatus.running => 'Vote submission in progress',
      VotingSubmissionJobStatus.waitingForKeystone =>
        'Waiting for Keystone signature',
      VotingSubmissionJobStatus.complete => 'Vote submission complete',
      VotingSubmissionJobStatus.error => 'Vote submission needs attention',
    };
  }

  String _detailFor(
    VotingSubmissionJobState job,
    VotingSessionState? session,
    String accountName,
  ) {
    if (job.status == VotingSubmissionJobStatus.error) {
      return 'Review the voting status';
    }
    if (job.status == VotingSubmissionJobStatus.complete) {
      return accountName;
    }
    final phase = session?.phase;
    final phaseLabel = switch (phase) {
      VotingSessionPhase.waitingForWalletSync => 'Waiting for sync',
      VotingSessionPhase.resolvingPir => 'Resolving voting data',
      VotingSessionPhase.loadingWitnesses => 'Generating proof inputs',
      VotingSessionPhase.readyToDelegate ||
      VotingSessionPhase.delegating => 'Delegating',
      VotingSessionPhase.keystoneSigning => 'Signing with Keystone',
      VotingSessionPhase.delegated => 'Delegated',
      VotingSessionPhase.readyToVote => 'Preparing vote',
      VotingSessionPhase.syncingVoteTree => 'Syncing vote tree',
      VotingSessionPhase.castingVotes => 'Casting votes',
      VotingSessionPhase.submittingShares => 'Submitting shares',
      VotingSessionPhase.done => 'Complete',
      VotingSessionPhase.error => 'Error',
      _ => 'Preparing',
    };
    return '$phaseLabel · $accountName';
  }

  double _progressFor(
    VotingSubmissionJobState job,
    VotingSessionState? session,
  ) {
    if (job.status == VotingSubmissionJobStatus.complete) return 1;
    if (job.status == VotingSubmissionJobStatus.error) return 1;
    if (job.status == VotingSubmissionJobStatus.waitingForKeystone) {
      return session?.voteSubmissionProgress?.clamp(0.0, 1.0).toDouble() ??
          0.55;
    }
    if (session == null) return 0.05;
    if (session.phase == VotingSessionPhase.waitingForWalletSync) {
      final scanned = session.walletScannedHeight;
      final snapshot = session.walletSnapshotHeight;
      if (scanned == null || snapshot == null || snapshot <= 0) return 0.1;
      return (scanned / snapshot).clamp(0.0, 1.0).toDouble();
    }
    if (session.phase == VotingSessionPhase.delegating) {
      return _delegationProgress(session);
    }
    return session.voteSubmissionProgress?.clamp(0.0, 1.0).toDouble() ?? 0.35;
  }

  double _delegationProgress(VotingSessionState session) {
    final indexes = <int>{
      ...?session.resumePlan?.pendingDelegationBundleIndexes,
      ...session.delegationProgress.keys,
      ?session.currentBundleIndex,
    }.toList()..sort();
    if (indexes.isEmpty) return 0.2;

    var completedProgress = 0.0;
    for (final bundleIndex in indexes) {
      final progress = session.delegationProgress[bundleIndex];
      if (progress?.phase == 'submitted' || progress?.phase == 'confirmed') {
        completedProgress += 1;
      } else {
        completedProgress +=
            progress?.proofProgress?.clamp(0.0, 1.0).toDouble() ?? 0;
      }
    }
    return (completedProgress / indexes.length).clamp(0.0, 1.0);
  }
}
