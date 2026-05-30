import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_api.dart';
import 'package:zcash_wallet/src/features/voting/voting_recovery_service.dart';
import 'package:zcash_wallet/src/features/voting/voting_resume_plan.dart';
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/wire.dart'
    as rust_frb_types;

import 'round_plan_test_utils.dart';

void main() {
  test('empty round resumes delegation for every bundle', () async {
    final api = FakeVotingRecoveryApi(state: recoveryState(bundleCount: 3));
    final service = VotingRecoveryService(api: api);

    final plan = await service.loadResumePlan(
      dbPath: 'wallet.db',
      walletId: 'wallet-1',
      roundId: 'round-1',
    );

    expect(plan.pendingDelegationBundleIndexes, [0, 1, 2]);
    expect(plan.pendingVoteSubmissionKeys, isEmpty);
    expect(plan.hasPendingWork, isTrue);
    expect(api.clearCalls, isEmpty);
  });

  test('mixed delegation hashes only resume missing bundle indexes', () async {
    final service = VotingRecoveryService(
      api: FakeVotingRecoveryApi(
        state: recoveryState(
          bundleCount: 4,
          delegationTxHashes: [
            delegationTx(bundleIndex: 0),
            delegationTx(bundleIndex: 2),
          ],
        ),
      ),
    );

    final plan = await service.loadResumePlan(
      dbPath: 'wallet.db',
      walletId: 'wallet-1',
      roundId: 'round-1',
    );

    expect(plan.pendingDelegationBundleIndexes, [1, 3]);
  });

  test(
    'submitted delegation resumes confirmation polling, not fresh submit',
    () async {
      final service = VotingRecoveryService(
        api: FakeVotingRecoveryApi(
          state: recoveryState(
            bundleCount: 3,
            delegationWorkflows: [
              delegationWorkflow(
                bundleIndex: 0,
                phase: VotingWorkflowPhase.confirmed,
              ),
              delegationWorkflow(
                bundleIndex: 1,
                phase: VotingWorkflowPhase.submittedDelegation,
                txHash: 'delegation-tx-1',
              ),
            ],
          ),
        ),
      );

      final plan = await service.loadResumePlan(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );

      expect(plan.pendingDelegationBundleIndexes, [2]);
      expect(plan.submittedDelegationBundleIndexes, [1]);
      expect(plan.hasPendingWork, isTrue);
    },
  );

  test(
    'vote records and tx hashes are matched by bundle and proposal',
    () async {
      final service = VotingRecoveryService(
        api: FakeVotingRecoveryApi(
          state: recoveryState(
            votes: [
              vote(bundleIndex: 0, proposalId: 1),
              vote(bundleIndex: 1, proposalId: 1),
              vote(bundleIndex: 1, proposalId: 2),
            ],
            voteTxHashes: [
              voteTx(bundleIndex: 1, proposalId: 1, txHash: 'tx-1-1'),
            ],
          ),
        ),
      );

      final plan = await service.loadResumePlan(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );

      expect(
        plan.voteTxHashFor(const VotingVoteKey(bundleIndex: 1, proposalId: 1)),
        'tx-1-1',
      );
      expect(plan.pendingVoteSubmissionKeys, [
        const VotingVoteKey(bundleIndex: 0, proposalId: 1),
        const VotingVoteKey(bundleIndex: 1, proposalId: 2),
      ]);
    },
  );

  test('commitment bundle recovery is surfaced for exact vote keys', () async {
    final service = VotingRecoveryService(
      api: FakeVotingRecoveryApi(
        state: recoveryState(
          votes: [
            vote(bundleIndex: 0, proposalId: 1),
            vote(bundleIndex: 1, proposalId: 1),
          ],
          voteTxHashes: [voteTx(bundleIndex: 1, proposalId: 1)],
          commitmentBundles: [
            commitmentBundle(
              bundleIndex: 1,
              proposalId: 1,
              commitmentBundleJson: '{"bundle":"one"}',
              vcTreePosition: 42,
            ),
          ],
        ),
      ),
    );

    final plan = await service.loadResumePlan(
      dbPath: 'wallet.db',
      walletId: 'wallet-1',
      roundId: 'round-1',
    );

    final missingKey = const VotingVoteKey(bundleIndex: 0, proposalId: 1);
    final recoveredKey = const VotingVoteKey(bundleIndex: 1, proposalId: 1);

    expect(plan.commitmentBundleFor(missingKey), isNull);
    expect(
      plan.commitmentBundleFor(recoveredKey)?.commitmentBundleJson,
      '{"bundle":"one"}',
    );
    expect(
      plan.commitmentBundleFor(recoveredKey)?.vcTreePosition,
      BigInt.from(42),
    );
    expect(plan.incompleteVoteRecoveryKeys, [missingKey]);
  });

  test(
    'submitted votes resume confirmation polling and confirmed votes vanish',
    () async {
      final submittedKey = const VotingVoteKey(bundleIndex: 0, proposalId: 1);
      final confirmedKey = const VotingVoteKey(bundleIndex: 1, proposalId: 1);
      final service = VotingRecoveryService(
        api: FakeVotingRecoveryApi(
          state: recoveryState(
            votes: [
              vote(
                bundleIndex: submittedKey.bundleIndex,
                proposalId: submittedKey.proposalId,
              ),
              vote(
                bundleIndex: confirmedKey.bundleIndex,
                proposalId: confirmedKey.proposalId,
              ),
            ],
            voteWorkflows: [
              voteWorkflow(
                bundleIndex: submittedKey.bundleIndex,
                proposalId: submittedKey.proposalId,
                phase: VotingWorkflowPhase.submittedVote,
                txHash: 'vote-tx-submitted',
                hasCommitmentBundle: true,
              ),
              voteWorkflow(
                bundleIndex: confirmedKey.bundleIndex,
                proposalId: confirmedKey.proposalId,
                phase: VotingWorkflowPhase.confirmed,
                txHash: 'vote-tx-confirmed',
                vcTreePosition: 42,
                hasCommitmentBundle: true,
              ),
            ],
            voteTxHashes: [
              voteTx(
                bundleIndex: submittedKey.bundleIndex,
                proposalId: submittedKey.proposalId,
                txHash: 'vote-tx-submitted',
              ),
              voteTx(
                bundleIndex: confirmedKey.bundleIndex,
                proposalId: confirmedKey.proposalId,
                txHash: 'vote-tx-confirmed',
              ),
            ],
            commitmentBundles: [
              commitmentBundle(
                bundleIndex: submittedKey.bundleIndex,
                proposalId: submittedKey.proposalId,
              ),
              commitmentBundle(
                bundleIndex: confirmedKey.bundleIndex,
                proposalId: confirmedKey.proposalId,
                vcTreePosition: 42,
              ),
            ],
          ),
        ),
      );

      final plan = await service.loadResumePlan(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );

      expect(plan.pendingVoteSubmissionKeys, isEmpty);
      expect(plan.submittedVoteConfirmationKeys, [submittedKey]);
      expect(plan.incompleteVoteRecoveryKeys, isEmpty);
      expect(plan.votePhasesByKey[confirmedKey], VotingWorkflowPhase.confirmed);
    },
  );

  test('only unconfirmed share delegations are returned for retry', () async {
    final confirmed = share(shareIndex: 0, confirmed: true);
    final unconfirmed = share(shareIndex: 1, confirmed: false);
    final service = VotingRecoveryService(
      api: FakeVotingRecoveryApi(
        state: recoveryState(
          shareDelegations: [confirmed, unconfirmed],
          // Keep the service conservative even if a caller supplies stale data.
          unconfirmedShareDelegations: [confirmed, unconfirmed],
        ),
      ),
    );

    final plan = await service.loadResumePlan(
      dbPath: 'wallet.db',
      walletId: 'wallet-1',
      roundId: 'round-1',
    );

    expect(plan.shareDelegations, [confirmed, unconfirmed]);
    expect(plan.unconfirmedShareDelegations, [unconfirmed]);
  });

  test(
    'accepted unconfirmed shares do not block foreground completion',
    () async {
      final accepted = share(shareIndex: 0, confirmed: false);
      final service = VotingRecoveryService(
        api: FakeVotingRecoveryApi(
          state: recoveryState(
            shareDelegations: [accepted],
            unconfirmedShareDelegations: [accepted],
          ),
        ),
      );

      final plan = await service.loadResumePlan(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );

      expect(plan.unconfirmedShareDelegations, [accepted]);
      expect(plan.hasBlockingShareWork, isFalse);
      expect(plan.hasPendingWork, isFalse);
    },
  );

  test(
    'share-only round planner work does not block accepted share completion',
    () async {
      final accepted = share(shareIndex: 0, confirmed: false);
      final plan = VotingRecoveryService().buildResumePlan(
        recoveryState(
          shareDelegations: [accepted],
          unconfirmedShareDelegations: [accepted],
        ),
      );
      final roundPlan = apiRoundPlan(
        roundId: 'round-1',
        pendingRecovery: true,
        nextSteps: const [
          rust_frb_types.NextStepView(
            kind: 'confirm_share',
            bundleIndex: 0,
            proposalId: 1,
            choice: 0,
            shareIndex: 0,
          ),
        ],
        openProposals: Uint32List(0),
        allDecided: true,
      );

      expect(
        hasBlockingRoundRecoveryWork(roundPlan: roundPlan, resumePlan: plan),
        isFalse,
      );
    },
  );

  test('round planner vote work blocks foreground completion', () {
    final roundPlan = apiRoundPlan(
      roundId: 'round-1',
      pendingRecovery: true,
      nextSteps: const [
        rust_frb_types.NextStepView(
          kind: 'poll_vote',
          bundleIndex: 0,
          proposalId: 1,
          choice: 0,
          shareIndex: 0,
        ),
      ],
      openProposals: Uint32List(0),
      allDecided: false,
    );

    expect(
      hasBlockingRoundRecoveryWork(roundPlan: roundPlan, resumePlan: null),
      isTrue,
    );
  });

  test(
    'unaccepted share recovery still blocks foreground completion',
    () async {
      final unaccepted = share(
        shareIndex: 0,
        confirmed: false,
        sentToUrls: const [],
      );
      final service = VotingRecoveryService(
        api: FakeVotingRecoveryApi(
          state: recoveryState(
            shareDelegations: [unaccepted],
            unconfirmedShareDelegations: [unaccepted],
          ),
        ),
      );

      final plan = await service.loadResumePlan(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );

      expect(plan.unconfirmedShareDelegations, [unaccepted]);
      expect(plan.hasBlockingShareWork, isTrue);
      expect(plan.hasPendingWork, isTrue);
    },
  );

  test(
    'finalize and abandon clear recovery state but loading does not',
    () async {
      final api = FakeVotingRecoveryApi(state: recoveryState());
      final service = VotingRecoveryService(api: api);

      await service.loadResumePlan(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );
      expect(api.clearCalls, isEmpty);

      await service.finalizeRound(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-1',
      );
      await service.abandonRound(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        roundId: 'round-2',
      );

      expect(api.clearCalls, ['round-1', 'round-2']);
    },
  );

  test(
    'addSentServersForShare forwards exact share key and new URLs',
    () async {
      final api = FakeVotingRecoveryApi(state: recoveryState());
      final service = VotingRecoveryService(api: api);
      final record = share(bundleIndex: 2, proposalId: 3, shareIndex: 4);

      await service.addSentServersForShare(
        dbPath: 'wallet.db',
        walletId: 'wallet-1',
        share: record,
        newUrls: ['https://helper-b.example'],
      );

      expect(api.addSentServersCalls, [
        const AddSentServersCall(
          roundId: 'round-1',
          bundleIndex: 2,
          proposalId: 3,
          shareIndex: 4,
          newUrls: ['https://helper-b.example'],
        ),
      ]);
    },
  );
}

class FakeVotingRecoveryApi implements VotingRecoveryApi {
  FakeVotingRecoveryApi({required this.state});

  rust_frb_types.RoundRecoveryStateView state;
  final clearCalls = <String>[];
  final addSentServersCalls = <AddSentServersCall>[];

  @override
  Future<rust_frb_types.RoundRecoveryStateView> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    return state;
  }

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) async {
    addSentServersCalls.add(
      AddSentServersCall(
        roundId: roundId,
        bundleIndex: bundleIndex,
        proposalId: proposalId,
        shareIndex: shareIndex,
        newUrls: newUrls,
      ),
    );
  }

  @override
  Future<rust_frb_types.RoundPlanView> getRoundPlan({
    required String dbPath,
    required String walletId,
    required String roundId,
    required List<int> proposalIds,
  }) async {
    return apiRoundPlan(
      roundId: roundId,
      pendingRecovery: false,
      nextSteps: const [],
      openProposals: Uint32List(0),
      allDecided: false,
    );
  }

  @override
  Future<void> setBallotIntent({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int proposalId,
    required int numOptions,
    required bool skipped,
    int? choice,
  }) async {}

  @override
  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    clearCalls.add(roundId);
  }
}

class AddSentServersCall {
  final String roundId;
  final int bundleIndex;
  final int proposalId;
  final int shareIndex;
  final List<String> newUrls;

  const AddSentServersCall({
    required this.roundId,
    required this.bundleIndex,
    required this.proposalId,
    required this.shareIndex,
    required this.newUrls,
  });

  @override
  int get hashCode => Object.hash(
    roundId,
    bundleIndex,
    proposalId,
    shareIndex,
    Object.hashAll(newUrls),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddSentServersCall &&
          runtimeType == other.runtimeType &&
          roundId == other.roundId &&
          bundleIndex == other.bundleIndex &&
          proposalId == other.proposalId &&
          shareIndex == other.shareIndex &&
          _listEquals(newUrls, other.newUrls);
}

rust_frb_types.RoundRecoveryStateView recoveryState({
  int bundleCount = 0,
  List<rust_frb_types.DelegationRecoveryView> delegationTxHashes = const [],
  List<rust_frb_types.DelegationRecoveryView> delegationWorkflows = const [],
  List<rust_frb_types.VoteRecoveryView> votes = const [],
  List<rust_frb_types.VoteRecoveryView> voteWorkflows = const [],
  List<rust_frb_types.VoteRecoveryView> voteTxHashes = const [],
  List<rust_frb_types.CommitmentBundleRecoveryView> commitmentBundles =
      const [],
  List<rust_frb_types.ShareWorkflowRecoveryView> shareWorkflows = const [],
  List<rust_frb_types.ShareDelegationRecordView> shareDelegations = const [],
  List<rust_frb_types.ShareDelegationRecordView> unconfirmedShareDelegations =
      const [],
}) {
  final delegationByBundle = <int, rust_frb_types.DelegationRecoveryView>{
    for (final record in delegationWorkflows) record.bundleIndex: record,
  };
  for (final record in delegationTxHashes) {
    delegationByBundle[record.bundleIndex] =
        rust_frb_types.DelegationRecoveryView(
          bundleIndex: record.bundleIndex,
          phase: record.phase,
          txHash: record.txHash,
          vanLeafPosition: record.vanLeafPosition,
        );
  }

  final votesByKey = <String, rust_frb_types.VoteRecoveryView>{
    for (final record in votes)
      '${record.bundleIndex}:${record.proposalId}': record,
    for (final record in voteWorkflows)
      '${record.bundleIndex}:${record.proposalId}': record,
  };
  for (final record in voteTxHashes) {
    final key = '${record.bundleIndex}:${record.proposalId}';
    final current = votesByKey[key];
    votesByKey[key] = rust_frb_types.VoteRecoveryView(
      bundleIndex: record.bundleIndex,
      proposalId: record.proposalId,
      choice: current?.choice ?? record.choice,
      phase: current?.phase ?? VotingWorkflowPhase.submittedVote,
      txHash: record.txHash,
      vcTreePosition: current?.vcTreePosition ?? record.vcTreePosition,
      hasCommitmentBundle:
          current?.hasCommitmentBundle ?? record.hasCommitmentBundle,
    );
  }

  return rust_frb_types.RoundRecoveryStateView(
    roundId: 'round-1',
    bundleCount: bundleCount,
    delegation: delegationByBundle.values.toList(),
    votes: votesByKey.values.toList(),
    commitmentBundles: commitmentBundles,
    shares: shareWorkflows,
    shareDelegations: shareDelegations,
    unconfirmedShareDelegations: unconfirmedShareDelegations,
  );
}

rust_frb_types.DelegationRecoveryView delegationWorkflow({
  required int bundleIndex,
  required String phase,
  String? txHash,
  int? vanLeafPosition,
}) {
  return rust_frb_types.DelegationRecoveryView(
    bundleIndex: bundleIndex,
    phase: phase,
    txHash: txHash,
    vanLeafPosition: vanLeafPosition,
  );
}

rust_frb_types.DelegationRecoveryView delegationTx({
  required int bundleIndex,
  String txHash = 'delegation-tx',
}) {
  return rust_frb_types.DelegationRecoveryView(
    bundleIndex: bundleIndex,
    phase: VotingWorkflowPhase.submittedDelegation,
    txHash: txHash,
    vanLeafPosition: null,
  );
}

rust_frb_types.VoteRecoveryView vote({
  required int bundleIndex,
  required int proposalId,
  int choice = 0,
}) {
  return rust_frb_types.VoteRecoveryView(
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    choice: choice,
    phase: VotingWorkflowPhase.prepared,
    hasCommitmentBundle: false,
  );
}

rust_frb_types.VoteRecoveryView voteTx({
  required int bundleIndex,
  required int proposalId,
  String txHash = 'vote-tx',
}) {
  return rust_frb_types.VoteRecoveryView(
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    choice: 0,
    phase: VotingWorkflowPhase.submittedVote,
    txHash: txHash,
    hasCommitmentBundle: false,
  );
}

rust_frb_types.VoteRecoveryView voteWorkflow({
  required int bundleIndex,
  required int proposalId,
  required String phase,
  String? txHash,
  int? vcTreePosition,
  bool hasCommitmentBundle = false,
}) {
  return rust_frb_types.VoteRecoveryView(
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    choice: 0,
    phase: phase,
    txHash: txHash,
    vcTreePosition: vcTreePosition == null ? null : BigInt.from(vcTreePosition),
    hasCommitmentBundle: hasCommitmentBundle,
  );
}

rust_frb_types.CommitmentBundleRecoveryView commitmentBundle({
  required int bundleIndex,
  required int proposalId,
  String commitmentBundleJson = '{}',
  int vcTreePosition = 0,
}) {
  return rust_frb_types.CommitmentBundleRecoveryView(
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    commitmentBundleJson: commitmentBundleJson,
    vcTreePosition: BigInt.from(vcTreePosition),
  );
}

rust_frb_types.ShareDelegationRecordView share({
  int bundleIndex = 0,
  int proposalId = 1,
  int shareIndex = 0,
  bool confirmed = false,
  List<String> sentToUrls = const ['https://helper-a.example'],
}) {
  return rust_frb_types.ShareDelegationRecordView(
    roundId: 'round-1',
    bundleIndex: bundleIndex,
    proposalId: proposalId,
    shareIndex: shareIndex,
    sentToUrls: sentToUrls,
    nullifier: Uint8List.fromList(List.filled(32, shareIndex)),
    phase: confirmed
        ? VotingWorkflowPhase.confirmed
        : VotingWorkflowPhase.submittedShare,
    confirmed: confirmed,
    submitAt: BigInt.zero,
    createdAt: BigInt.one,
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
