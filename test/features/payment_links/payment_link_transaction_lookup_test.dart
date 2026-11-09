import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_lookup.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_transaction_matching.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test(
    'index retains split rows and matches either byte order without duplication',
    () {
      final txid = '01${'ab' * 31}';
      final reversed = paymentLinkTxidInOtherByteOrder(txid)!;
      final sent = transaction(txid, 'sent');
      final received = transaction(txid, 'received');
      final unrelated = transaction('cd' * 32, 'received');
      final index = PaymentLinkTransactionIndex([sent, received, unrelated]);
      expect(index.matching('0x${txid.toUpperCase()},$reversed,$txid'), [
        sent,
        received,
      ]);
      expect(index.matching('missing'), isEmpty);
      expect(index.matching(null), isEmpty);
      expect(
        paymentLinkFundingTransactionsExist(
          fundingTxids: reversed,
          transactions: index.matching(reversed),
        ),
        isTrue,
      );
      expect(
        paymentLinkFundingExpired(
          fundingTxids: reversed,
          transactions: index.matching(reversed),
        ),
        isFalse,
      );
    },
  );

  test(
    'multi-leg and overlapping proposals always share one query snapshot',
    () async {
      final requests = <String, Set<String>>{};
      String txid(int id) => id.toRadixString(16).padLeft(64, '0');
      for (var i = 1; i <= 63; i++) {
        addPaymentLinkTransactionIds(requests, 'account', txid(i));
      }
      addPaymentLinkTransactionIds(
        requests,
        'account',
        '${txid(64)},${txid(65)}',
      );
      addPaymentLinkTransactionIds(
        requests,
        'account',
        '${txid(65)},${txid(66)}',
      );
      final calls = <List<String>>[];
      await loadPaymentLinkTransactionRows(
        dbPath: 'unused',
        network: 'main',
        txidsByAccount: requests,
        loadRows: (_, ids) async {
          calls.add(ids);
          return [];
        },
      );
      expect(calls.length, 2);
      final proposalCalls = calls
          .where((ids) => ids.contains(txid(64)))
          .toList();
      expect(proposalCalls.length, 1);
      expect(proposalCalls.single, containsAll([txid(64), txid(65), txid(66)]));
      final allIds = calls.expand((ids) => ids).toList();
      expect(allIds.length, allIds.toSet().length);
    },
  );

  test(
    'lookup deduplicates requests per account and bounds each bridge response',
    () async {
      final requests = <String, Set<String>>{};
      for (var i = 1; i <= 200; i++) {
        addPaymentLinkTransactionIds(
          requests,
          'first',
          i.toRadixString(16).padLeft(64, '0'),
        );
      }
      addPaymentLinkTransactionIds(
        requests,
        'second',
        ' ${'cd' * 32},0x${'CD' * 32} ',
      );
      requests['empty'] = {};
      final seen = <String, Set<String>>{};
      var calls = 0;
      final result = await loadPaymentLinkTransactionRows(
        dbPath: 'unused',
        network: 'main',
        txidsByAccount: requests,
        loadRows: (account, ids) async {
          calls++;
          expect(ids.length, lessThanOrEqualTo(128));
          final previous = seen[account] ??= {};
          expect(ids.any(previous.contains), isFalse);
          previous.addAll(ids);
          return [for (final id in ids) transaction(id, 'sent')];
        },
      );
      expect(calls, 5);
      expect(seen['first']!.length, 400);
      expect(seen['second'], {'cd' * 32});
      expect(result['first']!.length, 400);
      expect(result['empty'], isEmpty);
    },
  );
}

rust_sync.TransactionInfo transaction(String txid, String kind) =>
    rust_sync.TransactionInfo(
      txidHex: txid,
      minedHeight: BigInt.from(119),
      expiredUnmined: false,
      accountBalanceDelta: -110000,
      fee: BigInt.from(10000),
      feeState: rust_sync.TransactionFeeState.known,
      detailsComplete: true,
      provisional: false,
      amountIncludesFee: false,
      blockTime: BigInt.zero,
      isTransparent: false,
      txKind: kind,
      displayAmount: BigInt.from(110000),
      displayPool: 'shielded',
      createdTime: BigInt.zero,
    );
