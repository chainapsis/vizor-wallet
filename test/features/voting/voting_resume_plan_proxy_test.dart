import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_wire;

import 'round_plan_test_utils.dart';

const _roundId =
    'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';

/// A step of [kind] on bundle [bundle], for DC slot [dcSlot] when given.
rust_wire.NextStepView _step(
  rust_wire.NextStepKind kind, {
  int bundle = 0,
  int proposal = 0,
  int? dcSlot,
}) => rust_wire.NextStepView(
  kind: kind,
  bundleIndex: bundle,
  proposalId: proposal,
  choice: 0,
  shareIndex: 0,
  dcSlot: dcSlot,
);

/// A plan listing [steps], with bundle 0 in [phase].
rust_wire.RoundPlanView _plan(
  List<rust_wire.NextStepView> steps, {
  rust_wire.WorkflowPhaseView phase = rust_wire.WorkflowPhaseView.confirmed,
}) => apiRoundPlan(
  roundId: _roundId,
  pendingRecovery: false,
  nextSteps: steps,
  openProposals: Uint32List(0),
  allDecided: true,
  recoveredVoteWork: const [],
  delegationStatuses: [
    rust_wire.DelegationStatusView(
      bundleIndex: 0,
      phase: phase,
      terminal: false,
    ),
  ],
);

void main() {
  test('a DC share delivery is proxy work, not a vote, and its confirmation '
      'is background tracking\'s', () {
    final dcShare = _step(rust_wire.NextStepKind.submitShares, dcSlot: 2);
    final dcConfirm = _step(rust_wire.NextStepKind.confirmShare, dcSlot: 2);
    final voteShare = _step(rust_wire.NextStepKind.submitShares, proposal: 1);
    final cast = _step(rust_wire.NextStepKind.castVote, proposal: 1);

    expect(isVoteNextStep(dcShare), isFalse);
    expect(isVoteNextStep(voteShare), isTrue);
    expect(isVoteNextStep(cast), isTrue);
    expect(isProxyNextStep(dcShare), isTrue);
    expect(isProxyNextStep(dcConfirm), isFalse);
    expect(isProxyNextStep(voteShare), isFalse);
    expect(
      isProxyNextStep(_step(rust_wire.NextStepKind.proxyDelegate)),
      isTrue,
    );
    expect(
      isProxyNextStep(_step(rust_wire.NextStepKind.advanceProxyBatch)),
      isTrue,
    );

    final plan = _plan([dcShare, voteShare.copyWithBundle(1)]);
    expect(voteCarryingBundleIndexes(plan), [1]);
  });

  test('a plan owes proxy work while any proxy step remains', () {
    expect(roundPlanHasProxyWork(null), isFalse);
    expect(
      roundPlanHasProxyWork(
        _plan([_step(rust_wire.NextStepKind.castVote, proposal: 1)]),
      ),
      isFalse,
    );
    expect(
      roundPlanHasProxyWork(
        _plan([_step(rust_wire.NextStepKind.submitShares, dcSlot: 0)]),
      ),
      isTrue,
    );
    expect(
      roundPlanHasProxyWork(
        _plan([_step(rust_wire.NextStepKind.confirmShare, dcSlot: 0)]),
      ),
      isFalse,
    );
  });

  test('only a batch on an unconfirmed registration proves it', () {
    final proving = [_step(rust_wire.NextStepKind.proxyDelegate)];
    expect(roundPlanProxyNeedsRegistrationProof(_plan(proving)), isFalse);
    expect(
      roundPlanProxyNeedsRegistrationProof(
        _plan(proving, phase: rust_wire.WorkflowPhaseView.prepared),
      ),
      isTrue,
    );
    expect(
      roundPlanProxyNeedsRegistrationProof(
        _plan([
          _step(rust_wire.NextStepKind.advanceProxyBatch),
        ], phase: rust_wire.WorkflowPhaseView.prepared),
      ),
      isFalse,
    );
  });

  test('the kept bundles that sign at their first cast leave out batch, '
      'fully delegated, signed-on-chain and terminal bundles', () {
    rust_wire.DelegationStatusView status(
      int bundle,
      rust_wire.WorkflowPhaseView phase, {
      bool terminal = false,
    }) => rust_wire.DelegationStatusView(
      bundleIndex: bundle,
      phase: phase,
      terminal: terminal,
    );
    final plan = apiRoundPlan(
      roundId: _roundId,
      pendingRecovery: true,
      nextSteps: [_step(rust_wire.NextStepKind.proxyDelegate, bundle: 1)],
      openProposals: Uint32List.fromList(const [1]),
      allDecided: false,
      recoveredVoteWork: const [],
      delegationStatuses: [
        // Fully delegated: casts nothing.
        status(0, rust_wire.WorkflowPhaseView.prepared),
        // Its batch carries the registration's signature.
        status(1, rust_wire.WorkflowPhaseView.prepared),
        status(2, rust_wire.WorkflowPhaseView.prepared),
        status(3, rust_wire.WorkflowPhaseView.signed),
        status(4, rust_wire.WorkflowPhaseView.confirmed),
        status(5, rust_wire.WorkflowPhaseView.submittedDelegation),
        status(6, rust_wire.WorkflowPhaseView.prepared, terminal: true),
        // A batch that already left the plan's steps.
        status(7, rust_wire.WorkflowPhaseView.prepared),
      ],
      fullyDelegatedBundles: const [0],
      proxyBatches: const [
        rust_wire.ProxyBatchStatusView(
          bundleIndex: 7,
          stage: rust_wire.ProxyBatchStageView.landed,
        ),
      ],
    );

    expect(keptBundlesSigningFirstCast(plan), [2, 3]);
    expect(keptBundlesSigningFirstCast(null), isEmpty);
  });
}

extension on rust_wire.NextStepView {
  /// This step on bundle [bundle].
  rust_wire.NextStepView copyWithBundle(int bundle) => rust_wire.NextStepView(
    kind: kind,
    bundleIndex: bundle,
    proposalId: proposalId,
    choice: choice,
    shareIndex: shareIndex,
    dcSlot: dcSlot,
  );
}
