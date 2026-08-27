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
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    createCalls++;
    if (record != null) return const PrivateStateCreateConflict();
    record = VotingCompletionRecord.decode(
      plaintext,
      expectedRoundId: key.itemKey.substring('round-v1:'.length),
    );
    return const PrivateStateCreated();
  }

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    readCalls++;
    final value = record;
    if (value == null) return const PrivateStateReadAbsent();
    return PrivateStateReadFound(plaintext: value.encode());
  }
}
