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
      transactionCompletenessSignature(
        _transaction('aa', 'sent', amountIsNetChange: true),
      ),
    };
    expect(signatures, hasLength(5));
  });

  test('a net change is the account\'s own fee only when that equals it', () {
    TransactionFeePresentation presentation({
      required bool amountIsNetChange,
      required int displayAmount,
      rust_sync.TransactionFeeState feeState =
          rust_sync.TransactionFeeState.known,
    }) => transactionFeePresentation(
      _transaction(
        'aa',
        'sent',
        amountIsNetChange: amountIsNetChange,
        accountBalanceDelta: -displayAmount,
        displayAmount: BigInt.from(displayAmount),
        feeState: feeState,
      ),
    );

    // The fee is 10000 zatoshis.
    expect(
      presentation(amountIsNetChange: false, displayAmount: 100000),
      TransactionFeePresentation.separate,
    );
    expect(
      presentation(amountIsNetChange: false, displayAmount: 10000),
      TransactionFeePresentation.separate,
      reason: 'a payment equal to the fee is still a payment',
    );
    expect(
      presentation(amountIsNetChange: true, displayAmount: 100000),
      TransactionFeePresentation.netChange,
    );
    expect(
      presentation(amountIsNetChange: true, displayAmount: 10000),
      TransactionFeePresentation.feeOnly,
    );
    expect(
      presentation(
        amountIsNetChange: true,
        displayAmount: 10000,
        feeState: rust_sync.TransactionFeeState.wholeTransaction,
      ),
      TransactionFeePresentation.netChange,
      reason: 'the whole transaction\'s fee is not the account\'s',
    );
  });
  test('net movement equal to the whole fee does not establish fee-only', () {
    // A mixed-pool movement can be provisional or settled without its payment
    // role being established. Neither becomes a fee-only entry.
    for (final provisional in [true, false]) {
      final tx = _transaction(
        'aa',
        'sent',
        detailsComplete: false,
        provisional: provisional,
        feeState: rust_sync.TransactionFeeState.wholeTransaction,
        amountIsNetChange: true,
        displayAmount: BigInt.from(20000),
        fee: BigInt.from(20000),
        accountBalanceDelta: -20000,
        displayPool: 'unknown',
      );
      expect(
        transactionFeePresentation(tx),
        TransactionFeePresentation.netChange,
      );
      expect(transactionDetailsIncomplete(tx), isTrue);
    }
  });

  test('established self-transfer can lack recipient details', () {
    final tx = _transaction(
      'aa',
      'sent',
      detailsComplete: false,
      amountIsNetChange: true,
      displayAmount: BigInt.from(10000),
      accountBalanceDelta: -10000,
      displayPool: 'unknown',
    );
    expect(transactionFeePresentation(tx), TransactionFeePresentation.feeOnly);
    expect(transactionDetailsIncomplete(tx), isTrue);
  });

  test('an unsettled change of the fee is not established fee-only', () {
    final tx = _transaction(
      'aa',
      'sent',
      provisional: true,
      amountIsNetChange: true,
      displayAmount: BigInt.from(10000),
      accountBalanceDelta: -10000,
      displayPool: 'unknown',
    );
    expect(
      transactionFeePresentation(tx),
      TransactionFeePresentation.netChange,
    );
  });

  test('fee-only requires a known fee attributed to the account debit', () {
    for (final state in [
      rust_sync.TransactionFeeState.unknown,
      rust_sync.TransactionFeeState.notApplicable,
      rust_sync.TransactionFeeState.wholeTransaction,
    ]) {
      final tx = _transaction(
        'aa',
        'sent',
        feeState: state,
        amountIsNetChange: true,
        displayPool: 'unknown',
        accountBalanceDelta: -10000,
        displayAmount: BigInt.from(10000),
      );
      expect(
        transactionFeePresentation(tx),
        TransactionFeePresentation.netChange,
      );
    }
    final sharedFee = _transaction(
      'aa',
      'sent',
      amountIsNetChange: true,
      displayPool: 'unknown',
      accountBalanceDelta: -5000,
      displayAmount: BigInt.from(10000),
    );
    expect(
      transactionFeePresentation(sharedFee),
      TransactionFeePresentation.netChange,
    );
  });

  test('complete shielding keeps its transfer amount and separate fee', () {
    final tx = _transaction(
      'aa',
      'shielded',
      displayAmount: BigInt.from(400000),
      fee: BigInt.from(20000),
      accountBalanceDelta: -20000,
    );
    expect(transactionFeePresentation(tx), TransactionFeePresentation.separate);
  });
}

rust_sync.TransactionInfo _transaction(
  String txid,
  String kind, {
  bool detailsComplete = true,
  bool provisional = false,
  rust_sync.TransactionFeeState feeState = rust_sync.TransactionFeeState.known,
  bool amountIsNetChange = false,
  BigInt? displayAmount,
  BigInt? fee,
  int accountBalanceDelta = 0,
  String displayPool = 'shielded',
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: BigInt.from(2500000),
    expiredUnmined: false,
    accountBalanceDelta: accountBalanceDelta,
    fee: fee ?? BigInt.from(10000),
    feeState: feeState,
    detailsComplete: detailsComplete,
    provisional: provisional,
    amountIsNetChange: amountIsNetChange,
    blockTime: BigInt.from(1750000000),
    isTransparent: displayPool == 'transparent',
    txKind: kind,
    displayAmount: displayAmount ?? BigInt.from(100000),
    displayPool: displayPool,
    createdTime: BigInt.from(1750000000),
  );
}
