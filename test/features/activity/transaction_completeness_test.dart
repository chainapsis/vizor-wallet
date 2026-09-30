import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('a provisional role follows the transaction only to a single row', () {
    bool matches(String txid) => txid == 'aa';
    final shielded = _transaction('aa', 'shielded');

    expect(provisionalRoleSuccessor([shielded], matches), same(shielded));
    expect(
      provisionalRoleSuccessor([
        shielded,
        _transaction('bb', 'received'),
      ], matches),
      same(shielded),
      reason: 'other transactions do not count',
    );
    expect(
      provisionalRoleSuccessor([
        shielded,
        _transaction('aa', 'received'),
      ], matches),
      isNull,
      reason: 'one leg of several is never picked',
    );
    expect(provisionalRoleSuccessor(const [], matches), isNull);
  });

  test('the completeness signature changes with each completeness field', () {
    final base = _transaction('aa', 'sent');
    final signatures = {
      transactionCompletenessSignature(base),
      transactionCompletenessSignature(
        _transaction('aa', 'sent', detailsComplete: false),
      ),
      transactionCompletenessSignature(
        _transaction('aa', 'sent', provisional: true),
      ),
      transactionCompletenessSignature(
        _transaction(
          'aa',
          'sent',
          feeState: rust_sync.TransactionFeeState.unknown,
        ),
      ),
    };
    expect(signatures, hasLength(4));
  });
}

rust_sync.TransactionInfo _transaction(
  String txid,
  String kind, {
  bool detailsComplete = true,
  bool provisional = false,
  rust_sync.TransactionFeeState feeState = rust_sync.TransactionFeeState.known,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: BigInt.from(2500000),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.from(10000),
    feeState: feeState,
    detailsComplete: detailsComplete,
    provisional: provisional,
    blockTime: BigInt.from(1750000000),
    isTransparent: false,
    txKind: kind,
    displayAmount: BigInt.from(100000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1750000000),
  );
}
