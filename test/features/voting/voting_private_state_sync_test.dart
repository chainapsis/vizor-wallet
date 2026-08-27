import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_private_state_sync.dart';
import 'package:zcash_wallet/src/providers/voting/voting_service_providers.dart';

void main() {
  const account = PrivateStateAccount(
    dbPath: '/wallet.db',
    network: 'main',
    accountUuid: 'local-account',
  );

  test('completion payload round-trips choices including skipped votes', () {
    final record = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: 1_717_260_000,
      choicesByProposalId: {9: null, 7: 1},
    );

    final decoded = VotingCompletionRecord.decode(
      record.encode(),
      expectedRoundId: 'round-42',
    );

    expect(decoded.completedAtSeconds, 1_717_260_000);
    expect(decoded.choicesByProposalId.keys, [7, 9]);
    expect(decoded.choicesByProposalId, {7: 1, 9: null});
  });

  test('completion payload is bound to the requested round', () {
    final record = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: null,
      choicesByProposalId: const {},
    );

    expect(
      () => VotingCompletionRecord.decode(
        record.encode(),
        expectedRoundId: 'round-43',
      ),
      throwsA(isA<PrivateStateProtocolException>()),
    );
  });

  test('concurrent publish returns immutable remote winner', () async {
    final repository = _ConflictRepository();
    final sync = VotingPrivateStateSync(repository);
    final candidate = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: 20,
      choicesByProposalId: const {7: 1},
    );

    final winner = await sync.publishCompletion(
      account: account,
      record: candidate,
    );

    expect(winner.completedAtSeconds, 10);
    expect(winner.choicesByProposalId, {7: 0});
  });

  test('reports remotely read and locally published completions', () async {
    final repository = _MemoryRepository();
    final observed = <VotingCompletionRecord>[];
    final sync = VotingPrivateStateSync(
      repository,
      onCompletionObserved: (_, record) => observed.add(record),
    );
    final record = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: 20,
      choicesByProposalId: const {7: 1},
    );

    await sync.publishCompletion(account: account, record: record);
    await sync.readCompletion(account: account, roundId: 'round-42');

    expect(observed, [record, isA<VotingCompletionRecord>()]);
  });

  test('completion revision changes only for new account-round content', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      votingPrivateCompletionRevisionProvider.notifier,
    );
    const revisionAccount = PrivateStateAccount(
      dbPath: 'wallet.db',
      network: 'main',
      accountUuid: 'account-1',
    );
    final first = VotingCompletionRecord(
      roundId: 'round-1',
      completedAtSeconds: 1,
      choicesByProposalId: const {7: 0},
    );

    notifier.observe(account: revisionAccount, record: first);
    notifier.observe(account: revisionAccount, record: first);
    expect(container.read(votingPrivateCompletionRevisionProvider), 1);

    notifier.observe(
      account: revisionAccount,
      record: VotingCompletionRecord(
        roundId: 'round-1',
        completedAtSeconds: 2,
        choicesByProposalId: const {7: 1},
      ),
    );
    expect(container.read(votingPrivateCompletionRevisionProvider), 2);
  });
}

class _ConflictRepository implements PrivateStateObjectRepository {
  final winner = VotingCompletionRecord(
    roundId: 'round-42',
    completedAtSeconds: 10,
    choicesByProposalId: const {7: 0},
  );

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async => const PrivateStateCreateConflict();

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    return PrivateStateReadFound(plaintext: winner.encode());
  }
}

class _MemoryRepository implements PrivateStateObjectRepository {
  Uint8List? plaintext;

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    this.plaintext = Uint8List.fromList(plaintext);
    return const PrivateStateCreated();
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    return PrivateStateReadFound(plaintext: Uint8List.fromList(plaintext!));
  }
}
