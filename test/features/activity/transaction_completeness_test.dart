import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/transaction_completeness.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import '../../support/test_l10n.dart';

void main() {
  test('one notice covers several rows waiting on the private check', () {
    final waiting = _transaction('aa', 'received', provisional: true);
    final alsoWaiting = _transaction('bb', 'received', provisional: true);
    final settled = _transaction('cc', 'received');
    PrivateCheckNoticeState? notice(
      List<rust_sync.TransactionInfo> txs, {
      bool privateQueriesEnabled = true,
      rust_sync.TransparentStopReason? stop,
    }) => privateCheckNotice(
      txs,
      privateQueriesEnabled: privateQueriesEnabled,
      stop: stop,
    );

    expect(
      notice([waiting, alsoWaiting, settled]),
      const PrivateCheckNoticeState.checking(),
    );
    // An expired transaction is never mined into coverage.
    final expired = _transaction(
      'dd',
      'received',
      provisional: true,
      expiredUnmined: true,
    );
    expect(notice([waiting, expired]), isNull);
    // A single new receive keeps its own label.
    expect(notice([waiting, settled]), isNull);
    expect(
      notice([waiting, alsoWaiting], privateQueriesEnabled: false),
      isNull,
    );
  });

  test('a stopped check shows why on any row it left', () {
    final waiting = _transaction('aa', 'received', provisional: true);
    final settled = _transaction('cc', 'received');
    const stalled = rust_sync.TransparentStopReason.stalled;

    expect(
      privateCheckNotice(
        [waiting, settled],
        privateQueriesEnabled: true,
        stop: stalled,
      ),
      const PrivateCheckNoticeState.stopped(stalled),
    );
    // Turning Private queries off did not finish, so the setting reads off.
    expect(
      privateCheckNotice(
        [waiting],
        privateQueriesEnabled: false,
        stop: rust_sync.TransparentStopReason.optOutUnfinished,
      ),
      const PrivateCheckNoticeState.stopped(
        rust_sync.TransparentStopReason.optOutUnfinished,
      ),
    );
    // Nothing waits, so the list has nothing to explain.
    expect(
      privateCheckNotice([settled], privateQueriesEnabled: true, stop: stalled),
      isNull,
    );
  });

  test('only the stops the user clears point to Settings', () {
    expect(
      [
        for (final stop in rust_sync.TransparentStopReason.values)
          if (transparentStopNeedsSettings(stop)) stop,
      ],
      unorderedEquals([
        rust_sync.TransparentStopReason.quarantined,
        rust_sync.TransparentStopReason.legacyDiscrepancy,
        rust_sync.TransparentStopReason.optOutUnfinished,
      ]),
    );
  });

  test('a stopped receipt explains why its details are incomplete', () {
    const stalled = rust_sync.TransparentStopReason.stalled;
    final waiting = _transaction('aa', 'received', provisional: true);
    expect(receiptPrivateCheckStop(waiting, stop: stalled), stalled);
    expect(
      receiptPrivateCheckStop(_transaction('cc', 'received'), stop: stalled),
      isNull,
    );
    expect(
      receiptIncompleteDetailsHelp(
        testL10n,
        awaitsPrivateCheck: false,
        stop: stalled,
      ),
      '${testL10n.activityReceiptDetailsIncompleteHelp}\n\n'
      '${testL10n.homeTransparentStopStalled}',
    );
    expect(
      receiptIncompleteDetailsHelp(
        testL10n,
        awaitsPrivateCheck: true,
        stop: null,
      ),
      testL10n.activityReceiptCheckingPrivatelyHelp,
    );
  });

  test('a receipt waits on the private check only for unsettled effects', () {
    expect(
      receiptAwaitsPrivateCheck(
        _transaction('aa', 'received', provisional: true),
        recoveryStopped: false,
      ),
      isTrue,
    );
    expect(
      receiptAwaitsPrivateCheck(
        _transaction('aa', 'received', provisional: true),
        recoveryStopped: true,
      ),
      isFalse,
    );
    // Missing payment details are not the private check's to finish.
    expect(
      receiptAwaitsPrivateCheck(
        _transaction('aa', 'sent', provisional: true, detailsComplete: false),
        recoveryStopped: false,
      ),
      isFalse,
    );
    expect(
      receiptAwaitsPrivateCheck(
        _transaction('aa', 'received', detailsComplete: false),
        recoveryStopped: false,
      ),
      isFalse,
    );
    expect(
      receiptAwaitsPrivateCheck(
        _transaction('aa', 'received', provisional: true, expiredUnmined: true),
        recoveryStopped: false,
      ),
      isFalse,
    );
  });

  test('a send the wallet just built waits on scanning, not the check', () {
    // Unmined: its shielded side is still unsettled too.
    final justSent = _transaction(
      'aa',
      'sent',
      provisional: true,
      mined: false,
    );
    expect(entryAwaitsPrivateCheck(justSent), isFalse);
    expect(
      receiptAwaitsPrivateCheck(justSent, recoveryStopped: false),
      isFalse,
    );
    expect(
      privateCheckNotice(
        [justSent, _transaction('bb', 'sent', provisional: true, mined: false)],
        privateQueriesEnabled: true,
        stop: null,
      ),
      isNull,
    );
    expect(
      receiptPrivateCheckStop(
        justSent,
        stop: rust_sync.TransparentStopReason.stalled,
      ),
      isNull,
    );
  });

  test('network fee is display-only and bound to the receipt identity', () {
    final tx = _transaction(
      'aa',
      'sent',
      feeState: rust_sync.TransactionFeeState.unknown,
      fee: BigInt.zero,
      detailsComplete: false,
      provisional: true,
      accountBalanceDelta: -5000,
    );
    rust_sync.TransactionDetail detail({
      String txid = 'aa',
      String kind = 'sent',
      BigInt? fee,
    }) => rust_sync.TransactionDetail(
      txidHex: txid,
      txKind: kind,
      networkFee: fee,
      outputs: const [],
      detailsComplete: false,
      provisional: true,
      transparentRecipients: const [],
      transparentOmissions: const ['shared_funding'],
    );
    expect(
      unattributedReceiptNetworkFee(tx, detail(fee: BigInt.from(15000))),
      BigInt.from(15000),
    );
    expect(
      unattributedReceiptNetworkFee(tx, detail(fee: BigInt.zero)),
      BigInt.zero,
    );
    expect(unattributedReceiptNetworkFee(tx, detail()), isNull);
    expect(
      unattributedReceiptNetworkFee(
        tx,
        detail(txid: 'bb', fee: BigInt.from(15000)),
      ),
      isNull,
    );
    expect(
      unattributedReceiptNetworkFee(
        tx,
        detail(kind: 'received', fee: BigInt.from(15000)),
      ),
      isNull,
    );
    expect(
      unattributedReceiptNetworkFee(
        _transaction('aa', 'sent'),
        detail(fee: BigInt.from(15000)),
      ),
      isNull,
    );
    expect(tx.accountBalanceDelta, -5000);
    expect(tx.feeState, rust_sync.TransactionFeeState.unknown);
    expect(tx.fee, BigInt.zero);
    expect(transactionDetailsIncomplete(tx), isTrue);
  });

  test('an unsettled receive whose details balance stays incomplete', () {
    // Rust keeps the detail of an unsettled receive provisional even when
    // its transparent outputs account for the balance; only a settled one
    // is complete and clears the entry's notice.
    final tx = _transaction(
      'aa',
      'received',
      feeState: rust_sync.TransactionFeeState.notApplicable,
      detailsComplete: false,
      provisional: true,
      accountBalanceDelta: 1000000,
    );
    rust_sync.TransactionDetail detail({required bool settled}) =>
        rust_sync.TransactionDetail(
          txidHex: 'aa',
          txKind: 'received',
          sourcePool: 'shielded',
          outputs: const [],
          detailsComplete: settled,
          provisional: !settled,
          transparentDetailsState: rust_sync.TransparentDetailsState.available,
          transparentRecipients: [
            rust_sync.TransparentRecipient(
              outputIndex: 0,
              address: 't1self',
              amountZatoshi: BigInt.from(1000000),
              isOwn: true,
            ),
          ],
          transparentOutputCount: 1,
          transparentOmissions: const [],
        );
    expect(transactionDetailsIncomplete(tx), isTrue);
    expect(receiptDetailsComplete(detail(settled: false)), isFalse);
    expect(receiptDetailsComplete(detail(settled: true)), isTrue);
  });

  test('conservative receipts label balance movements as net changes', () {
    expect(testL10n.activityReceiptNetChange, 'Net change');
  });

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

  test('the completeness signature changes with the fee presentation', () {
    // The fee is 10000 zatoshis; amount, fee and completeness stay the same.
    String signature({
      required bool amountIncludesFee,
      required int accountBalanceDelta,
    }) => transactionCompletenessSignature(
      _transaction(
        'aa',
        'sent',
        amountIncludesFee: amountIncludesFee,
        displayPool: 'transparent',
        accountBalanceDelta: accountBalanceDelta,
        displayAmount: BigInt.from(10000),
      ),
    );

    final signatures = {
      signature(amountIncludesFee: false, accountBalanceDelta: -10000),
      signature(amountIncludesFee: true, accountBalanceDelta: -10000),
      signature(amountIncludesFee: true, accountBalanceDelta: -20000),
    };
    expect(signatures, hasLength(3), reason: 'separate, feeOnly, included');
  });

  test('a fee the amount includes is presented once', () {
    TransactionFeePresentation presentation({
      required bool amountIncludesFee,
      required int displayAmount,
    }) => transactionFeePresentation(
      _transaction(
        'aa',
        'sent',
        amountIncludesFee: amountIncludesFee,
        displayPool: 'transparent',
        accountBalanceDelta: -displayAmount,
        displayAmount: BigInt.from(displayAmount),
      ),
    );

    // The fee is 10000 zatoshis.
    expect(
      presentation(amountIncludesFee: false, displayAmount: 100000),
      TransactionFeePresentation.separate,
    );
    expect(
      presentation(amountIncludesFee: false, displayAmount: 10000),
      TransactionFeePresentation.separate,
      reason: 'a payment equal to the fee is still a payment',
    );
    expect(
      presentation(amountIncludesFee: true, displayAmount: 100000),
      TransactionFeePresentation.includedInAmount,
    );
    expect(
      presentation(amountIncludesFee: true, displayAmount: 10000),
      TransactionFeePresentation.feeOnly,
    );
  });
  test('net movement equal to the whole fee does not establish fee-only', () {
    // A mixed-pool movement can be provisional or settled without its payment
    // role being established. Neither becomes a fee-only transparent transfer.
    for (final provisional in [true, false]) {
      final tx = _transaction(
        'aa',
        'sent',
        detailsComplete: false,
        provisional: provisional,
        amountIncludesFee: true,
        displayAmount: BigInt.from(20000),
        fee: BigInt.from(20000),
        accountBalanceDelta: -20000,
        displayPool: 'unknown',
      );
      expect(
        transactionFeePresentation(tx),
        TransactionFeePresentation.includedInAmount,
      );
      expect(transactionDetailsIncomplete(tx), isTrue);
    }
  });

  test('established self-transfer can lack recipient details', () {
    final tx = _transaction(
      'aa',
      'sent',
      detailsComplete: false,
      amountIncludesFee: true,
      displayAmount: BigInt.from(10000),
      accountBalanceDelta: -10000,
      displayPool: 'transparent',
    );
    expect(transactionFeePresentation(tx), TransactionFeePresentation.feeOnly);
    expect(transactionDetailsIncomplete(tx), isTrue);
  });

  test('an unsettled transparent transfer is not established fee-only', () {
    final tx = _transaction(
      'aa',
      'sent',
      provisional: true,
      amountIncludesFee: true,
      displayAmount: BigInt.from(10000),
      accountBalanceDelta: -10000,
      displayPool: 'transparent',
    );
    expect(
      transactionFeePresentation(tx),
      TransactionFeePresentation.includedInAmount,
    );
  });

  test('fee-only requires a known fee attributed to the account debit', () {
    for (final state in [
      rust_sync.TransactionFeeState.unknown,
      rust_sync.TransactionFeeState.notApplicable,
    ]) {
      final tx = _transaction(
        'aa',
        'sent',
        feeState: state,
        amountIncludesFee: true,
        displayPool: 'transparent',
        accountBalanceDelta: -10000,
        displayAmount: BigInt.from(10000),
      );
      expect(
        transactionFeePresentation(tx),
        TransactionFeePresentation.includedInAmount,
      );
    }
    final sharedFee = _transaction(
      'aa',
      'sent',
      amountIncludesFee: true,
      displayPool: 'transparent',
      accountBalanceDelta: -5000,
      displayAmount: BigInt.from(10000),
    );
    expect(
      transactionFeePresentation(sharedFee),
      TransactionFeePresentation.includedInAmount,
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
  bool amountIncludesFee = false,
  BigInt? displayAmount,
  BigInt? fee,
  int accountBalanceDelta = 0,
  String displayPool = 'shielded',
  bool expiredUnmined = false,
  bool mined = true,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: expiredUnmined || !mined ? BigInt.zero : BigInt.from(2500000),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: accountBalanceDelta,
    fee: fee ?? BigInt.from(10000),
    feeState: feeState,
    detailsComplete: detailsComplete,
    provisional: provisional,
    amountIncludesFee: amountIncludesFee,
    blockTime: BigInt.from(1750000000),
    isTransparent: displayPool == 'transparent',
    txKind: kind,
    displayAmount: displayAmount ?? BigInt.from(100000),
    displayPool: displayPool,
    createdTime: BigInt.from(1750000000),
  );
}
