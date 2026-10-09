import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../integration_test/regtest_mobile_ironwood_migration_many_notes_test.dart'
    show
        mobileManyNotePreparationLayers,
        validateMobilePreparationConfirmedLayer,
        validateMobilePreparationMempool,
        validateMobilePreparationTopology,
        validateMobilePreparationTransactionProof;

final _txA = List.filled(64, 'a').join();
final _txB = List.filled(64, 'b').join();
final _block = List.filled(64, 'c').join();

void main() {
  test('original 20-note pinned preparation has parallel roots', () {
    expect(mobileManyNotePreparationLayers(20, 1000020000), [2, 1, 1]);
  });

  test('original 500-note weighted preparation has five exact layers', () {
    expect(mobileManyNotePreparationLayers(500, 500000000), [35, 5, 2, 1, 1]);
  });

  test('does not infer an unverified funding shape', () {
    expect(
      () => mobileManyNotePreparationLayers(20, 500000000),
      throwsStateError,
    );
  });

  for (final (layers, publicTotalFee) in [
    (const [2, 1, 1], 320000),
    (const [35, 5, 2, 1, 1], 3520000),
  ]) {
    test('validates every stage index and round in $layers', () {
      validateMobilePreparationTopology(
        _stages(layers),
        layers,
        BigInt.from(publicTotalFee),
      );
    });
  }

  test('rejects a per-stage fee supplied as the public total fee', () {
    expect(
      () => validateMobilePreparationTopology(_stages([2, 1, 1]), [
        2,
        1,
        1,
      ], BigInt.from(80000)),
      throwsStateError,
    );
  });

  test('rejects missing and duplicate stage identities', () {
    final stages = _stages([2, 1, 1]);
    expect(
      () => validateMobilePreparationTopology(stages.take(3).toList(), [
        2,
        1,
        1,
      ], BigInt.from(320000)),
      throwsStateError,
    );
    stages[1] = _stage(0, 1);
    expect(
      () => validateMobilePreparationTopology(stages, [
        2,
        1,
        1,
      ], BigInt.from(320000)),
      throwsStateError,
    );
  });

  test('rejects self-reported wrong round, fee or confirmation policy', () {
    for (final wrong in [
      _stage(1, 2),
      _stage(1, 1, fee: 70000),
      _stage(1, 1, target: 1),
      _stage(1, 1, target: 10),
    ]) {
      final stages = _stages([2, 1, 1])..[1] = wrong;
      expect(
        () => validateMobilePreparationTopology(stages, [
          2,
          1,
          1,
        ], BigInt.from(320000)),
        throwsStateError,
      );
    }
  });

  test('requires exactly two unique first-round actual transaction ids', () {
    expect(
      validateMobilePreparationMempool(
        {
          'size': 2,
          'txids': [_txA, _txB],
        },
        2,
        {},
      ),
      [_txA, _txB],
    );
  });

  test('does not accept too few or extra mempool transactions', () {
    for (final count in [1, 3]) {
      expect(
        () => validateMobilePreparationMempool(
          {
            'size': count,
            'txids': [_txA, _txB],
          },
          2,
          {},
        ),
        throwsStateError,
      );
    }
  });

  test('rejects duplicate, malformed, missing and reused mempool ids', () {
    for (final ids in [
      [_txA, _txA],
      [_txA, 'invalid'],
      [_txA],
    ]) {
      expect(
        () =>
            validateMobilePreparationMempool({'size': 2, 'txids': ids}, 2, {}),
        throwsStateError,
      );
    }
    expect(
      () => validateMobilePreparationMempool(
        {
          'size': 2,
          'txids': [_txA, _txB],
        },
        2,
        {_txA},
      ),
      throwsStateError,
    );
  });

  test('both parallel roots need their own trusted canonical inclusion', () {
    validateMobilePreparationConfirmedLayer(_stages([2, 1, 1]), 1, 2, 500);
  });

  test('one completed root cannot stand in for its parallel sibling', () {
    final stages = _stages([2, 1, 1])
      ..[1] = _stage(
        1,
        1,
        state: rust_sync.MigrationPreparationTransactionState.broadcasted,
      );
    expect(
      () => validateMobilePreparationConfirmedLayer(stages, 1, 2, 500),
      throwsStateError,
    );
  });

  test('rejects shallow, unmined or outside-interval stage confirmation', () {
    for (final wrong in [
      _stage(1, 1, confirmations: 2),
      _stage(1, 1, confirmations: 4),
      _stage(1, 1, minedHeight: null),
      _stage(1, 1, minedHeight: 500),
      _stage(1, 1, minedHeight: 511),
    ]) {
      final stages = _stages([2, 1, 1])..[1] = wrong;
      expect(
        () => validateMobilePreparationConfirmedLayer(stages, 1, 2, 500),
        throwsStateError,
      );
    }
  });

  test('actual tx inclusion must match an exact generated block hash', () {
    validateMobilePreparationTransactionProof(_proof(), _txA, [_block]);
  });

  test('rejects foreign identity, shallow depth or foreign block proof', () {
    for (final result in [
      {'txid': _txB, 'confirmations': 10, 'blockhash': _block},
      {'txid': _txA, 'confirmations': 9, 'blockhash': _block},
      {'txid': _txA, 'confirmations': 10, 'blockhash': _txB},
    ]) {
      expect(
        () => validateMobilePreparationTransactionProof(result, _txA, [_block]),
        throwsStateError,
      );
    }
  });

  // zcashdRpc rejects HTTP/RPC errors before returning a decoded result. This
  // pure validator checks result fields, not the helper's error-envelope path.
  test('missing decoded transaction fields cannot become inclusion proof', () {
    for (final response in <Map<String, Object?>>[
      {},
      {'txid': _txA},
    ]) {
      expect(
        () =>
            validateMobilePreparationTransactionProof(response, _txA, [_block]),
        throwsStateError,
      );
    }
  });
}

Map<String, Object?> _proof() => {
  'txid': _txA,
  'confirmations': 10,
  'blockhash': _block,
};

List<rust_sync.MigrationPreparationTransactionStatus> _stages(
  List<int> layers,
) {
  var index = 0;
  return [
    for (var layer = 0; layer < layers.length; layer++)
      for (var count = 0; count < layers[layer]; count++)
        _stage(index++, layer + 1),
  ];
}

rust_sync.MigrationPreparationTransactionStatus _stage(
  int index,
  int round, {
  rust_sync.MigrationPreparationTransactionState state =
      rust_sync.MigrationPreparationTransactionState.completed,
  int? minedHeight = 501,
  int confirmations = 3,
  int target = 3,
  int fee = 80000,
}) => rust_sync.MigrationPreparationTransactionStatus(
  stageIndex: index,
  approximateValueZatoshi: BigInt.from(50001000),
  round: round,
  feeZatoshi: BigInt.from(fee),
  plannedHeight: 501,
  projectedHeight: 501,
  projectedCompletionHeight: 510,
  outputs: const [],
  state: state,
  minedHeight: minedHeight,
  confirmationCount: confirmations,
  confirmationTarget: target,
);
