import 'dart:typed_data';

import 'package:zcash_wallet/src/rust/third_party/zcash_voting/share_policy.dart'
    as rust_share_policy;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;
import 'package:zcash_wallet/src/services/voting/voting_rust_exception.dart';
import 'fake_round_recovery_state.dart';

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
      case rust_wire.NextStepKind.delegate:
        needsDelegationSigning = true;
      case rust_wire.NextStepKind.advanceDelegation:
        hasInFlightDelegation = true;
      case rust_wire.NextStepKind.advanceImportedDelegation:
        hasInFlightDelegation = true;
      case rust_wire.NextStepKind.castVote:
      case rust_wire.NextStepKind.advanceVote:
      case rust_wire.NextStepKind.advanceVoteBatch:
      case rust_wire.NextStepKind.submitShares:
        needsVotePolling = true;
        hasRemaining = true;
        hasRecoverable = true;
      case rust_wire.NextStepKind.confirmShare:
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
  bool? hasUnconfirmedShares,
  bool hotkeyBound = false,
  bool completedVoteArtifact = false,
  bool? completedForDisplay,
  rust_wire.CompletedVoteDisplayView? completedVoteDisplay,
  bool? needsDraftSetup,
  rust_wire.RoundPlanActionKind? primaryAction,
  List<rust_wire.DelegationStatusView>? delegationStatuses,
  int? bundleCount,
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
          (nextSteps.any(
                (step) => step.kind != rust_wire.NextStepKind.confirmShare,
              ) ||
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
    // Every `ConfirmShare` step stands for one unconfirmed share, so a plan
    // that lists any of them still has share tracking to do.
    hasUnconfirmedShares:
        hasUnconfirmedShares ??
        (blockingShareWork ||
            nextSteps.any(
              (step) => step.kind == rust_wire.NextStepKind.confirmShare,
            )),
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
    delegationStatuses:
        delegationStatuses ?? _delegationStatuses(bundleCount, nextSteps),
    recoveredDelegationWork: resolvedDelegationWork,
    recoveredVoteWork: resolvedVoteWork,
    openProposals: openProposals,
    immediateShareKey: immediateShareKey,
    immediateShareConfirmed: immediateShareConfirmed,
    allDecided: allDecided,
  );
}

rust_wire.RoundPlanView apiRoundPlanFromRecoveryState({
  required FakeRoundRecoveryState state,
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

  final delegationByBundle = {
    for (final record in state.delegation) record.bundleIndex: record,
  };

  if (!completedVoteArtifact) {
    for (var bundleIndex = 0; bundleIndex < state.bundleCount; bundleIndex++) {
      final delegation = delegationByBundle[bundleIndex];
      if (delegation != null &&
          delegation.phase == rust_wire.WorkflowPhaseView.submittedDelegation) {
        nextSteps.add(
          rust_wire.NextStepView(
            kind: rust_wire.NextStepKind.advanceDelegation,
            bundleIndex: bundleIndex,
            proposalId: 0,
            choice: 0,
            shareIndex: 0,
          ),
        );
        recoveredDelegationWork.add(
          rust_wire.DelegationRecoveryWorkView(
            kind: rust_wire.DelegationRecoveryWorkKindView.advanceDelegation,
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
    if (vote.phase == rust_wire.WorkflowPhaseView.signed) {
      nextSteps.add(
        rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.advanceVote,
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          choice: 0,
          shareIndex: 0,
        ),
      );
      recoveredVoteWork.add(
        rust_wire.VoteRecoveryWorkView(
          kind: rust_wire.VoteRecoveryWorkKindView.advanceVote,
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          shareIndexes: Uint32List(0),
        ),
      );
    } else if (vote.phase == rust_wire.WorkflowPhaseView.submittedVote &&
        txHash != null) {
      nextSteps.add(
        rust_wire.NextStepView(
          kind: rust_wire.NextStepKind.advanceVote,
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
          choice: 0,
          shareIndex: 0,
        ),
      );
      recoveredVoteWork.add(
        rust_wire.VoteRecoveryWorkView(
          kind: rust_wire.VoteRecoveryWorkKindView.advanceVote,
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
        kind: rust_wire.NextStepKind.confirmShare,
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
        kind: rust_wire.VoteRecoveryWorkKindView.submitShares,
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
      nextSteps.any(
        (step) => step.kind != rust_wire.NextStepKind.confirmShare,
      ) ||
      blockingShareWork;
  final completedForDisplay = completedVoteArtifact && !blockingRecovery;

  return apiRoundPlan(
    roundId: roundId,
    pendingRecovery: nextSteps.isNotEmpty,
    blockingRecovery: blockingRecovery,
    blockingShareWork: blockingShareWork,
    // One status per persisted bundle, phase from the durable delegation row.
    delegationStatuses: [
      for (var bundleIndex = 0; bundleIndex < state.bundleCount; bundleIndex++)
        rust_wire.DelegationStatusView(
          bundleIndex: bundleIndex,
          phase:
              delegationByBundle[bundleIndex]?.phase ??
              rust_wire.WorkflowPhaseView.prepared,
        ),
    ],
    hasUnconfirmedShares: state.unconfirmedShareDelegations.any(
      (share) => !share.confirmed,
    ),
    hotkeyBound:
        recoveredDelegationWork.any(
          (work) => work.phase != rust_wire.WorkflowPhaseView.prepared,
        ) ||
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

int? _choiceForProposal(FakeRoundRecoveryState state, int proposalId) {
  final choices = state.votes
      .where((vote) => vote.proposalId == proposalId)
      .map((vote) => vote.choice)
      .toSet();
  return choices.length == 1 ? choices.single : null;
}

BigInt? _latestShareCreatedAt(FakeRoundRecoveryState state) {
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
      if (step.kind == rust_wire.NextStepKind.delegate ||
          step.kind == rust_wire.NextStepKind.advanceDelegation)
        rust_wire.DelegationRecoveryWorkView(
          kind: step.kind == rust_wire.NextStepKind.delegate
              ? rust_wire.DelegationRecoveryWorkKindView.delegate
              : rust_wire.DelegationRecoveryWorkKindView.advanceDelegation,
          bundleIndex: step.bundleIndex,
          phase: step.kind == rust_wire.NextStepKind.advanceDelegation
              ? rust_wire.WorkflowPhaseView.submittedDelegation
              : rust_wire.WorkflowPhaseView.prepared,
          txHash: step.kind == rust_wire.NextStepKind.advanceDelegation
              ? 'delegation-tx'
              : null,
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
    if (step.kind == rust_wire.NextStepKind.advanceVote ||
        step.kind == rust_wire.NextStepKind.advanceVoteBatch) {
      // A step kind no longer says whether the transaction was dispatched:
      // submitting and polling are one `advance_vote` call. The recorded
      // `txHash` carries that distinction, so it defaults to absent
      // (undispatched) here. A test that needs an already-dispatched
      // generation passes `recoveredVoteWork` explicitly.
      work.add(
        rust_wire.VoteRecoveryWorkView(
          kind: step.kind == rust_wire.NextStepKind.advanceVote
              ? rust_wire.VoteRecoveryWorkKindView.advanceVote
              : rust_wire.VoteRecoveryWorkKindView.advanceVoteBatch,
          bundleIndex: step.bundleIndex,
          proposalId: step.proposalId,
          shareIndexes: Uint32List(0),
        ),
      );
    } else if (step.kind == rust_wire.NextStepKind.submitShares) {
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
        kind: rust_wire.VoteRecoveryWorkKindView.submitShares,
        bundleIndex: grouped.bundleIndex,
        proposalId: grouped.proposalId,
        vcTreePosition: BigInt.zero,
        shareIndexes: Uint32List.fromList(grouped.shares),
      ),
    );
  }
  return work;
}

rust_wire.RoundPlanActionKind _primaryAction({
  required List<rust_wire.NextStepView> nextSteps,
  required bool blockingRecovery,
  required bool blockingShareWork,
  required bool completedForDisplay,
}) {
  if (completedForDisplay) return rust_wire.RoundPlanActionKind.done;
  if (!blockingRecovery) return rust_wire.RoundPlanActionKind.idle;
  if (nextSteps.any(
    (step) =>
        step.kind == rust_wire.NextStepKind.delegate ||
        step.kind == rust_wire.NextStepKind.advanceDelegation,
  )) {
    return rust_wire.RoundPlanActionKind.delegate;
  }
  if (nextSteps.any(
    (step) =>
        step.kind == rust_wire.NextStepKind.castVote ||
        step.kind == rust_wire.NextStepKind.advanceVote ||
        step.kind == rust_wire.NextStepKind.advanceVoteBatch,
  )) {
    return rust_wire.RoundPlanActionKind.vote;
  }
  if (blockingShareWork ||
      nextSteps.any(
        (step) =>
            step.kind == rust_wire.NextStepKind.submitShares ||
            step.kind == rust_wire.NextStepKind.confirmShare,
      )) {
    return rust_wire.RoundPlanActionKind.submitShares;
  }
  return rust_wire.RoundPlanActionKind.idle;
}

/// Builds the typed bridge failure a scripted fake would surface for `kind`.
///
/// Production Rust returns `VotingErrorView` from every voting FRB call and the
/// bridge wrapper rethrows it as [VotingRustException]; fakes construct the
/// same pair so provider and screen code is exercised through its real
/// classification path.
VotingRustException votingRustError(
  rust_wire.VotingErrorKindView kind, {
  required String message,
  bool retryable = false,
  int? bundleIndex,
  BigInt? snapshotHeight,
  BigInt? requiredWeightZatoshi,
  BigInt? selectedWeightZatoshi,
  int? requiredNotes,
  int? selectedNotes,
}) {
  return VotingRustException(
    rust_wire.VotingErrorView(
      kind: kind,
      retryable: retryable,
      message: message,
      bundleIndex: bundleIndex,
      snapshotHeight: snapshotHeight,
      requiredWeightZatoshi: requiredWeightZatoshi,
      selectedWeightZatoshi: selectedWeightZatoshi,
      requiredNotes: requiredNotes,
      selectedNotes: selectedNotes,
    ),
  );
}

/// One delegation status per persisted bundle, as the SDK reports.
///
/// A plan fixture that names no statuses still describes a round whose bundles
/// exist; their phase comes from the delegation work the steps imply.
List<rust_wire.DelegationStatusView> _delegationStatuses(
  int? bundleCount,
  List<rust_wire.NextStepView> nextSteps,
) {
  final phases = <int, rust_wire.WorkflowPhaseView>{};
  for (final step in nextSteps) {
    switch (step.kind) {
      case rust_wire.NextStepKind.delegate:
        phases[step.bundleIndex] = rust_wire.WorkflowPhaseView.prepared;
      case rust_wire.NextStepKind.advanceDelegation:
      case rust_wire.NextStepKind.advanceImportedDelegation:
        phases[step.bundleIndex] =
            rust_wire.WorkflowPhaseView.submittedDelegation;
      default:
        break;
    }
  }
  final count =
      bundleCount ??
      (phases.isEmpty ? 0 : phases.keys.reduce((a, b) => a > b ? a : b) + 1);
  return [
    for (var bundleIndex = 0; bundleIndex < count; bundleIndex++)
      rust_wire.DelegationStatusView(
        bundleIndex: bundleIndex,
        phase: phases[bundleIndex] ?? rust_wire.WorkflowPhaseView.confirmed,
      ),
  ];
}

/// Fills a scripted plan's durable-row facts from the state behind it.
///
/// The SDK derives delegation statuses and outstanding share work from the
/// rows themselves, independent of which steps the plan lists, so a fixture
/// that scripts steps alone would otherwise describe a round with no bundles
/// and no shares to track.
rust_wire.RoundPlanView withDelegationStatusesFrom(
  rust_wire.RoundPlanView plan,
  FakeRoundRecoveryState state,
) {
  final phases = {
    for (final record in state.delegation) record.bundleIndex: record.phase,
  };
  return apiRoundPlan(
    roundId: plan.roundId,
    pendingRecovery: plan.pendingRecovery,
    blockingRecovery: plan.blockingRecovery,
    // Durable rows decide outstanding share work: a share no helper accepted
    // is blocking, and a confirmed one is finished no matter which steps the
    // fixture scripted.
    blockingShareWork: state.shareDelegations.isEmpty
        ? plan.blockingShareWork
        : state.unconfirmedShareDelegations.any(
            (share) => !share.confirmed && share.sentToUrls.isEmpty,
          ),
    hasUnconfirmedShares: state.shareDelegations.isEmpty
        ? plan.hasUnconfirmedShares
        : state.unconfirmedShareDelegations.any((share) => !share.confirmed),
    hotkeyBound: plan.hotkeyBound,
    completedVoteArtifact: plan.completedVoteArtifact,
    completedForDisplay: plan.completedForDisplay,
    completedVoteDisplay: plan.completedVoteDisplay,
    needsDraftSetup: plan.needsDraftSetup,
    primaryAction: plan.primaryAction,
    nextSteps: plan.nextSteps,
    delegationStatuses: plan.delegationStatuses.isNotEmpty
        ? plan.delegationStatuses
        : [
            for (
              var bundleIndex = 0;
              bundleIndex < state.bundleCount;
              bundleIndex++
            )
              rust_wire.DelegationStatusView(
                bundleIndex: bundleIndex,
                phase:
                    phases[bundleIndex] ?? rust_wire.WorkflowPhaseView.prepared,
              ),
          ],
    recoveredDelegationWork: plan.recoveredDelegationWork,
    recoveredVoteWork: plan.recoveredVoteWork,
    openProposals: plan.openProposals,
    immediateShareKey: plan.immediateShareKey,
    immediateShareConfirmed: plan.immediateShareConfirmed,
    allDecided: plan.allDecided,
  );
}
