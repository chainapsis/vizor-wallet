import 'dart:typed_data';

import 'package:zcash_wallet/src/rust/third_party/zcash_voting/share_policy.dart'
    as rust_share_policy;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;


/// Mirrors the SDK's `summarize_plan_work` so fixtures stay faithful to the
/// derived predicates the app now reads instead of matching step kinds.
class _PlanWork {
  const _PlanWork({
    required this.needsDelegationSigning,
    required this.hasInFlightDelegation,
    required this.needsVotePolling,
    required this.hasRemainingVoteOrShareWork,
    required this.hasRecoverableVoteOrShareWork,
  });

  final bool needsDelegationSigning;
  final bool hasInFlightDelegation;
  final bool needsVotePolling;
  final bool hasRemainingVoteOrShareWork;
  final bool hasRecoverableVoteOrShareWork;
}

_PlanWork _planWork(
  List<rust_wire.NextStepView> nextSteps,
  bool blockingShareWork,
) {
  var needsDelegationSigning = false;
  var hasInFlightDelegation = false;
  var needsVotePolling = false;
  var hasRemaining = false;
  var hasRecoverable = false;
  for (final step in nextSteps) {
    switch (step.kind) {
      case 'delegate':
        needsDelegationSigning = true;
      case 'advance_delegation':
        hasInFlightDelegation = true;
      case 'cast_vote':
      case 'advance_vote':
      case 'advance_vote_batch':
      case 'submit_shares':
        needsVotePolling = true;
        hasRemaining = true;
        hasRecoverable = true;
      case 'confirm_share':
        hasRecoverable = true;
        if (blockingShareWork) hasRemaining = true;
    }
  }
  return _PlanWork(
    needsDelegationSigning: needsDelegationSigning,
    hasInFlightDelegation: hasInFlightDelegation,
    needsVotePolling: needsVotePolling,
    hasRemainingVoteOrShareWork: hasRemaining,
    hasRecoverableVoteOrShareWork: hasRecoverable,
  );
}

rust_wire.RoundPlanView apiRoundPlan({
  required String roundId,
  required bool pendingRecovery,
  required List<rust_wire.NextStepView> nextSteps,
  required Uint32List openProposals,
  required bool allDecided,
  bool? blockingRecovery,
  bool blockingShareWork = false,
  bool hotkeyBound = false,
  bool completedVoteArtifact = false,
  bool? completedForDisplay,
  rust_wire.CompletedVoteDisplayView? completedVoteDisplay,
  bool? needsDraftSetup,
  String? primaryAction,
  List<rust_wire.DelegationStatusView> delegationStatuses = const [],
  List<rust_wire.DelegationRecoveryWorkView>? recoveredDelegationWork,
  List<rust_wire.VoteRecoveryWorkView>? recoveredVoteWork,
  rust_share_policy.ImmediateShareKey? immediateShareKey,
  bool immediateShareConfirmed = false,
}) {
  final resolvedDelegationWork =
      recoveredDelegationWork ?? _delegationRecoveryWork(nextSteps);
  final resolvedVoteWork = recoveredVoteWork ?? _voteRecoveryWork(nextSteps);
  final resolvedBlockingRecovery =
      blockingRecovery ??
      (pendingRecovery &&
          (nextSteps.any((step) => step.kind != 'confirm_share') ||
              blockingShareWork));
  final resolvedCompletedForDisplay =
      completedForDisplay ??
      (completedVoteArtifact && !resolvedBlockingRecovery);
  final resolvedNeedsDraftSetup =
      needsDraftSetup ??
      (!resolvedBlockingRecovery &&
          !allDecided &&
          nextSteps.isEmpty &&
          openProposals.isNotEmpty);

  final work = _planWork(nextSteps, blockingShareWork);

  return rust_wire.RoundPlanView(
    roundId: roundId,
    pendingRecovery: pendingRecovery,
    blockingRecovery: resolvedBlockingRecovery,
    blockingShareWork: blockingShareWork,
    hotkeyBound: hotkeyBound,
    completedVoteArtifact: completedVoteArtifact,
    completedForDisplay: resolvedCompletedForDisplay,
    completedVoteDisplay: completedVoteDisplay,
    needsDraftSetup: resolvedNeedsDraftSetup,
    needsDelegationSigning: work.needsDelegationSigning,
    hasInFlightDelegation: work.hasInFlightDelegation,
    needsVotePolling: work.needsVotePolling,
    hasRemainingVoteOrShareWork: work.hasRemainingVoteOrShareWork,
    hasRecoverableVoteOrShareWork: work.hasRecoverableVoteOrShareWork,
    primaryAction:
        primaryAction ??
        _primaryAction(
          nextSteps: nextSteps,
          blockingRecovery: resolvedBlockingRecovery,
          blockingShareWork: blockingShareWork,
          completedForDisplay: resolvedCompletedForDisplay,
        ),
    nextSteps: nextSteps,
    delegationStatuses: delegationStatuses,
    recoveredDelegationWork: resolvedDelegationWork,
    recoveredVoteWork: resolvedVoteWork,
    openProposals: openProposals,
    immediateShareKey: immediateShareKey,
    immediateShareConfirmed: immediateShareConfirmed,
    allDecided: allDecided,
  );
}

rust_wire.RoundPlanView apiRoundPlanFromRecoveryState({
  required rust_wire.RoundRecoveryStateView state,
  required String roundId,
  required List<int> proposalIds,
}) {
  final nextSteps = <rust_wire.NextStepView>[];
  final recoveredDelegationWork = <rust_wire.DelegationRecoveryWorkView>[];
  final recoveredVoteWork = <rust_wire.VoteRecoveryWorkView>[];
  final completedVoteArtifact =
      state.votes.isNotEmpty ||
      state.commitmentBundles.isNotEmpty ||
      state.shareDelegations.isNotEmpty;

  if (!completedVoteArtifact) {
    final delegationByBundle = {
      for (final record in state.delegation) record.bundleIndex: record,
    };
    for (var bundleIndex = 0; bundleIndex < state.bundleCount; bundleIndex++) {
      final delegation = delegationByBundle[bundleIndex];
      if (delegation != null && delegation.phase == 'submitted_delegation') {
        nextSteps.add(
          rust_wire.NextStepView(
            kind: 'advance_delegation',
            bundleIndex: bundleIndex,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
        );
        recoveredDelegationWork.add(
          rust_wire.DelegationRecoveryWorkView(
            kind: 'advance_delegation',
            bundleIndex: bundleIndex,
            phase: delegation.phase,
            txHash: delegation.txHash,
          ),
        );
      }
    }
  }

  for (final vote in state.votes) {
    final txHash = vote.txHash;
    if (vote.phase == 'signed') {
      nextSteps.add(
        rust_wire.NextStepView(
          kind: 'advance_vote',
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          choice: 0,
          shareIndex: 0,
        ),
      );
      recoveredVoteWork.add(
        rust_wire.VoteRecoveryWorkView(
          kind: 'advance_vote',
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          shareIndexes: Uint32List(0),
        ),
      );
    } else if (vote.phase == 'submitted_vote' && txHash != null) {
      nextSteps.add(
        rust_wire.NextStepView(
          kind: 'advance_vote',
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          choice: 0,
          shareIndex: 0,
        ),
      );
      recoveredVoteWork.add(
        rust_wire.VoteRecoveryWorkView(
          kind: 'advance_vote',
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          txHash: txHash,
          shareIndexes: Uint32List(0),
        ),
      );
    }
  }

  final shareGroups =
      <
        String,
        ({int bundleIndex, int proposalId, List<int> shares, BigInt? position})
      >{};
  for (final share in state.unconfirmedShareDelegations) {
    nextSteps.add(
      rust_wire.NextStepView(
        kind: 'confirm_share',
        bundleIndex: share.bundleIndex,
        proposalId: share.proposalId,
        choice: 0,
        shareIndex: share.shareIndex,
      ),
    );
    if (share.sentToUrls.isEmpty) {
      final key = '${share.bundleIndex}:${share.proposalId}';
      final bundle = state.commitmentBundles
          .where(
            (item) =>
                item.bundleIndex == share.bundleIndex &&
                item.proposalId == share.proposalId,
          )
          .firstOrNull;
      final existing = shareGroups[key];
      if (existing == null) {
        shareGroups[key] = (
          bundleIndex: share.bundleIndex,
          proposalId: share.proposalId,
          shares: [share.shareIndex],
          position: bundle?.vcTreePosition,
        );
      } else {
        existing.shares.add(share.shareIndex);
      }
    }
  }
  for (final group in shareGroups.values) {
    recoveredVoteWork.add(
      rust_wire.VoteRecoveryWorkView(
        kind: 'submit_shares',
        bundleIndex: group.bundleIndex,
        proposalId: group.proposalId,
        vcTreePosition: group.position,
        shareIndexes: Uint32List.fromList(group.shares),
      ),
    );
  }

  final blockingShareWork = state.unconfirmedShareDelegations.any(
    (share) => share.sentToUrls.isEmpty,
  );
  final blockingRecovery =
      nextSteps.any((step) => step.kind != 'confirm_share') ||
      blockingShareWork;
  final completedForDisplay = completedVoteArtifact && !blockingRecovery;

  return apiRoundPlan(
    roundId: roundId,
    pendingRecovery: nextSteps.isNotEmpty,
    blockingRecovery: blockingRecovery,
    blockingShareWork: blockingShareWork,
    hotkeyBound:
        recoveredDelegationWork.any((work) => work.phase != 'prepared') ||
        completedVoteArtifact,
    completedVoteArtifact: completedVoteArtifact,
    completedForDisplay: completedForDisplay,
    completedVoteDisplay: completedForDisplay
        ? rust_wire.CompletedVoteDisplayView(
            choices: [
              for (final proposalId in proposalIds)
                rust_wire.CompletedVoteChoiceView(
                  proposalId: proposalId,
                  choice: _choiceForProposal(state, proposalId),
                ),
            ],
            votedAt: _latestShareCreatedAt(state),
          )
        : null,
    nextSteps: nextSteps,
    recoveredDelegationWork: recoveredDelegationWork,
    recoveredVoteWork: recoveredVoteWork,
    openProposals: Uint32List.fromList(proposalIds),
    allDecided: proposalIds.isNotEmpty && completedForDisplay,
  );
}

int? _choiceForProposal(
  rust_wire.RoundRecoveryStateView state,
  int proposalId,
) {
  final choices = state.votes
      .where((vote) => vote.proposalId == proposalId)
      .map((vote) => vote.choice)
      .toSet();
  return choices.length == 1 ? choices.single : null;
}

BigInt? _latestShareCreatedAt(rust_wire.RoundRecoveryStateView state) {
  final timestamps = state.shareDelegations
      .map((share) => share.createdAt)
      .where((createdAt) => createdAt > BigInt.zero)
      .toList();
  if (timestamps.isEmpty) return null;
  timestamps.sort();
  return timestamps.last;
}

List<rust_wire.DelegationRecoveryWorkView> _delegationRecoveryWork(
  List<rust_wire.NextStepView> steps,
) {
  return [
    for (final step in steps)
      if (step.kind == 'delegate' || step.kind == 'advance_delegation')
        rust_wire.DelegationRecoveryWorkView(
          kind: step.kind,
          bundleIndex: step.bundleIndex,
          phase: step.kind == 'advance_delegation'
              ? 'submitted_delegation'
              : 'prepared',
          txHash: step.kind == 'advance_delegation' ? 'delegation-tx' : null,
        ),
  ];
}

List<rust_wire.VoteRecoveryWorkView> _voteRecoveryWork(
  List<rust_wire.NextStepView> steps,
) {
  final groupedShares =
      <String, ({int bundleIndex, int proposalId, List<int> shares})>{};
  final work = <rust_wire.VoteRecoveryWorkView>[];
  for (final step in steps) {
    if (step.kind == 'advance_vote' || step.kind == 'advance_vote_batch') {
      // A step kind no longer says whether the transaction was dispatched:
      // submitting and polling are one `advance_vote` call. The recorded
      // `txHash` carries that distinction, so it defaults to absent
      // (undispatched) here. A test that needs an already-dispatched
      // generation passes `recoveredVoteWork` explicitly.
      work.add(
        rust_wire.VoteRecoveryWorkView(
          kind: step.kind,
          bundleIndex: step.bundleIndex,
          proposalId: step.proposalId,
          shareIndexes: Uint32List(0),
        ),
      );
    } else if (step.kind == 'submit_shares') {
      final key = '${step.bundleIndex}:${step.proposalId}';
      final existing = groupedShares[key];
      if (existing == null) {
        groupedShares[key] = (
          bundleIndex: step.bundleIndex,
          proposalId: step.proposalId,
          shares: [step.shareIndex],
        );
      } else {
        existing.shares.add(step.shareIndex);
      }
    }
  }
  for (final grouped in groupedShares.values) {
    work.add(
      rust_wire.VoteRecoveryWorkView(
        kind: 'submit_shares',
        bundleIndex: grouped.bundleIndex,
        proposalId: grouped.proposalId,
        vcTreePosition: BigInt.zero,
        shareIndexes: Uint32List.fromList(grouped.shares),
      ),
    );
  }
  return work;
}

String _primaryAction({
  required List<rust_wire.NextStepView> nextSteps,
  required bool blockingRecovery,
  required bool blockingShareWork,
  required bool completedForDisplay,
}) {
  if (completedForDisplay) return 'done';
  if (!blockingRecovery) return 'idle';
  if (nextSteps.any(
    (step) => step.kind == 'delegate' || step.kind == 'advance_delegation',
  )) {
    return 'delegate';
  }
  if (nextSteps.any(
    (step) =>
        step.kind == 'cast_vote' ||
        step.kind == 'vote' ||
        step.kind == 'advance_vote' ||
        step.kind == 'advance_vote',
  )) {
    return 'vote';
  }
  if (blockingShareWork ||
      nextSteps.any(
        (step) => step.kind == 'submit_shares' || step.kind == 'confirm_share',
      )) {
    return 'submit_shares';
  }
  return 'idle';
}
