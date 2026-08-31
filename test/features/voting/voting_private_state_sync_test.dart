import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_private_state_sync.dart';

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

  test(
    'publish conflict confirms existence without a follow-up read',
    () async {
      final repository = _ConflictRepository();
      final sync = VotingPrivateStateSync(repository);
      final candidate = VotingCompletionRecord(
        roundId: 'round-42',
        completedAtSeconds: 20,
        choicesByProposalId: const {7: 1},
      );

      await sync.publishCompletion(account: account, record: candidate);
      await sync.publishCompletion(account: account, record: candidate);
      expect(
        await sync.readCompletion(account: account, roundId: 'round-42'),
        same(candidate),
      );

      expect(repository.createCalls, 1);
      expect(repository.readCalls, 0);
    },
  );

  test('confirmed completion suppresses later reads and publishes', () async {
    final repository = _MemoryRepository();
    final sync = VotingPrivateStateSync(repository);
    final record = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: 20,
      choicesByProposalId: const {7: 1},
    );

    await sync.publishCompletion(account: account, record: record);
    expect(
      await sync.readCompletion(account: account, roundId: 'round-42'),
      same(record),
    );
    await sync.publishCompletion(account: account, record: record);

    expect(repository.createCalls, 1);
    expect(repository.readCalls, 0);
  });

  test('concurrent publications share one create request', () async {
    final repository = _MemoryRepository();
    final sync = VotingPrivateStateSync(repository);
    final record = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: 20,
      choicesByProposalId: const {7: 1},
    );

    await Future.wait([
      sync.publishCompletion(account: account, record: record),
      sync.publishCompletion(account: account, record: record),
    ]);

    expect(repository.createCalls, 1);
  });

  test('found completion suppresses later reads', () async {
    final repository = _MemoryRepository();
    final sync = VotingPrivateStateSync(repository);
    final record = VotingCompletionRecord(
      roundId: 'round-42',
      completedAtSeconds: 20,
      choicesByProposalId: const {7: 1},
    );
    repository.plaintext = record.encode();

    final first = await sync.readCompletion(
      account: account,
      roundId: 'round-42',
    );
    final second = await sync.readCompletion(
      account: account,
      roundId: 'round-42',
    );

    expect(first?.choicesByProposalId, {7: 1});
    expect(second, same(first));
    expect(repository.readCalls, 1);
  });

  test('absent completion is not cached', () async {
    final repository = _MemoryRepository();
    final sync = VotingPrivateStateSync(repository);

    expect(
      await sync.readCompletion(account: account, roundId: 'round-42'),
      isNull,
    );
    expect(
      await sync.readCompletion(account: account, roundId: 'round-42'),
      isNull,
    );

    expect(repository.readCalls, 2);
  });
}

class _ConflictRepository implements PrivateStateObjectRepository {
  int createCalls = 0;
  int readCalls = 0;

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createCalls++;
    return const PrivateStateCreateConflict();
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    readCalls++;
    return const PrivateStateReadAbsent();
  }
}

class _MemoryRepository implements PrivateStateObjectRepository {
  Uint8List? plaintext;
  int createCalls = 0;
  int readCalls = 0;

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createCalls++;
    this.plaintext = Uint8List.fromList(plaintext);
    return const PrivateStateCreated();
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    readCalls++;
    final value = plaintext;
    return value == null
        ? const PrivateStateReadAbsent()
        : PrivateStateReadFound(plaintext: Uint8List.fromList(value));
  }
}
