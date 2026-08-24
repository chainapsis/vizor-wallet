import 'dart:typed_data';

import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_object_repository.dart';
import 'package:zcash_wallet/src/features/voting/voting_private_state_sync.dart';

class MemoryVotingCompletionRepository implements PrivateStateObjectRepository {
  MemoryVotingCompletionRepository({this.record});

  VotingCompletionRecord? record;
  int createCalls = 0;
  int readCalls = 0;

  @override
  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createCalls++;
    if (record != null) return const PrivateStateWriteConflict();
    record = VotingCompletionRecord.decode(
      plaintext,
      expectedRoundId: key.itemKey.substring('round-v1:'.length),
    );
    return PrivateStateWriteStored(
      PrivateStateVersion(
        revision: BigInt.one,
        envelopeHashBase64: 'memory-hash',
      ),
    );
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    readCalls++;
    final value = record;
    if (value == null) return const PrivateStateReadAbsent();
    return PrivateStateReadFound(
      plaintext: value.encode(),
      version: PrivateStateVersion(
        revision: BigInt.one,
        envelopeHashBase64: 'memory-hash',
      ),
    );
  }

  @override
  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  }) {
    throw UnsupportedError('Voting completion objects are immutable.');
  }
}
