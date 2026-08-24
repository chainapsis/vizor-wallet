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
}

class _ConflictRepository implements PrivateStateObjectRepository {
  final winner = VotingCompletionRecord(
    roundId: 'round-42',
    completedAtSeconds: 10,
    choicesByProposalId: const {7: 0},
  );

  @override
  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  }) => throw UnimplementedError();

  @override
  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async => const PrivateStateWriteConflict();

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    return PrivateStateReadFound(
      plaintext: winner.encode(),
      version: PrivateStateVersion(
        revision: BigInt.one,
        envelopeHashBase64: 'winner-hash',
      ),
    );
  }
}
