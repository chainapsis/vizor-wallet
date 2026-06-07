import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_batch.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' show ReservedPcztBatchItem;
import 'package:zcash_wallet/src/rust/wallet/keystone.dart'
    show ZcashBatchSignResult, ZcashBatchSignedMessage;

ReservedPcztBatchItem item(String id, List<String> nfs) => ReservedPcztBatchItem(
      id: id,
      pcztWithProofs: Uint8List(0),
      redactedPczt: Uint8List(0),
      feeZatoshi: BigInt.zero,
      spendNullifiers: nfs,
    );

ZcashBatchSignedMessage signed(String id) => ZcashBatchSignedMessage(
      id: id,
      status: 1,
      kind: 1,
      signedPcztBytes: Uint8List(0),
      payloadDigestHex: '',
    );

void main() {
  test('verifyDistinctNotes passes when all notes are unique', () {
    expect(
      () => verifyDistinctNotes([
        item('tx-1', const ['orchard:aa']),
        item('tx-2', const ['orchard:bb']),
        item('tx-3', const ['orchard:cc']),
      ]),
      returnsNormally,
    );
  });

  test('verifyDistinctNotes throws on a shared note', () {
    expect(
      () => verifyDistinctNotes([
        item('tx-1', const ['orchard:aa']),
        item('tx-2', const ['orchard:aa']),
      ]),
      throwsA(isA<MigrationBatchError>()),
    );
  });

  test('verifySignResult accepts a matching result', () {
    final result = ZcashBatchSignResult(
        version: 1,
        requestId: 'req-1',
        results: [signed('tx-1'), signed('tx-2'), signed('tx-3')]);
    expect(
      () => verifySignResult(result, 'req-1', {'tx-1', 'tx-2', 'tx-3'}),
      returnsNormally,
    );
  });

  test('verifySignResult rejects wrong request id and mismatched ids', () {
    final wrongReq = ZcashBatchSignResult(
        version: 1, requestId: 'other', results: [signed('tx-1')]);
    expect(() => verifySignResult(wrongReq, 'req-1', {'tx-1'}),
        throwsA(isA<MigrationBatchError>()));
    final wrongIds = ZcashBatchSignResult(
        version: 1,
        requestId: 'req-1',
        results: [signed('tx-1'), signed('tx-9')]);
    expect(() => verifySignResult(wrongIds, 'req-1', {'tx-1', 'tx-2'}),
        throwsA(isA<MigrationBatchError>()));
  });
}
