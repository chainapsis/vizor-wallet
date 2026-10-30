import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/activity_history_pager.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust;

rust.TransactionInfo tx(int n, {String kind = 'received'}) =>
    rust.TransactionInfo(
      txidHex: n.toRadixString(16).padLeft(64, '0'),
      minedHeight: BigInt.from(100),
      expiredUnmined: false,
      accountBalanceDelta: 100,
      fee: BigInt.zero,
      feeState: rust.TransactionFeeState.notApplicable,
      detailsComplete: true,
      provisional: false,
      amountIncludesFee: false,
      blockTime: BigInt.from(100000),
      createdTime: BigInt.zero,
      isTransparent: false,
      txKind: kind,
      displayAmount: BigInt.from(100),
      displayPool: 'shielded',
    );

class Source implements ActivityHistorySource {
  Source(int count) : transactions = List.generate(count, (i) => tx(i + 1));
  List<rust.TransactionInfo> transactions;
  int version = 1;
  int indexReads = 0;
  final requests = <List<String>>[];
  Set<String> hidden = {};
  bool split = false;
  bool splitAll = false;
  bool failIndex = false;
  bool fail = false;
  Completer<void>? wait;
  bool invalidate = false;

  @override
  Future<rust.ActivityHistoryIndex> index() async {
    indexReads++;
    if (failIndex) throw StateError('index failed');
    return rust.ActivityHistoryIndex(
      snapshotId: '$version',
      summaries: [
        for (var i = 0; i < transactions.length; i++)
          rust.ActivityHistorySummary(
            txidHex: transactions[i].txidHex,
            minedHeight: transactions[i].minedHeight,
            expiredUnmined: false,
            blockTime: transactions[i].blockTime,
            createdTime: transactions[i].createdTime,
            sourceOrder: i,
          ),
      ],
    );
  }

  @override
  Future<rust.ActivityHistoryRows> rows(
    String snapshot,
    List<String> txids,
  ) async {
    requests.add([...txids]);
    await wait?.future;
    if (fail) throw StateError('read failed');
    if (invalidate) {
      invalidate = false;
      transactions.insert(0, tx(999));
      version++;
    }
    return rust.ActivityHistoryRows(
      stale: snapshot != '$version',
      transactions: [
        if (snapshot == '$version')
          for (final item in transactions)
            if (txids.contains(item.txidHex) &&
                !hidden.contains(item.txidHex)) ...[
              item,
              if (splitAll || (split && item == transactions.first))
                tx(int.parse(item.txidHex, radix: 16), kind: 'sent'),
            ],
      ],
    );
  }
}

ActivityHistoryPager pager(
  Source source, {
  GiftCardActivityIndex? gifts,
  bool mobile = false,
}) => ActivityHistoryPager(
  source: source,
  gifts: () => gifts ?? GiftCardActivityIndex.empty,
  swaps: () => const [],
  mobile: mobile,
);

void main() {
  for (final mobile in [false, true]) {
    test(
      '20-row pages reuse summaries and bound details, mobile=$mobile',
      () async {
        final source = Source(65);
        final p = pager(source, mobile: mobile);
        addTearDown(p.dispose);
        await p.load();
        expect(p.transactions, hasLength(20));
        expect(p.visibleCount, 20);
        expect(source.requests.map((r) => r.length), [20]);
        await p.load(more: true);
        expect(p.transactions, hasLength(40));
        expect(p.visibleCount, 40);
        expect(source.indexReads, 1);
        expect(source.requests.map((r) => r.length), [20, 20]);
        await p.load(more: true);
        await p.load(more: true);
        expect(p.transactions, source.transactions);
        expect(p.hasMore, isFalse);
        expect(source.requests.expand((r) => r).toSet(), hasLength(65));
      },
    );
  }

  test('large account ordering runs through the background planner', () async {
    final source = Source(1200);
    final p = pager(source);
    addTearDown(p.dispose);
    await p.load();
    expect(p.error, isNull);
    expect(p.transactions, hasLength(20));
    expect(source.indexReads, 1);
    expect(source.requests.map((r) => r.length), [20]);
  });

  test(
    'split rows are buffered and hidden rows do not consume quota',
    () async {
      final source = Source(65)..split = true;
      final p = pager(source);
      addTearDown(p.dispose);
      await p.load();
      expect(p.transactions, hasLength(21));
      expect(p.visibleCount, 20);
      await p.load(more: true);
      expect(p.transactions, hasLength(41));
      expect(p.visibleCount, 40);
      expect(source.requests.map((r) => r.length), [20, 20]);

      final hidden = Source(65);
      hidden.hidden = hidden.transactions
          .take(25)
          .map((t) => t.txidHex)
          .toSet();
      final h = pager(hidden);
      addTearDown(h.dispose);
      await h.load();
      expect(h.transactions, hasLength(35));
      expect(h.visibleCount, 20);
      expect(hidden.requests.every((r) => r.length <= 20), isTrue);
      expect(hidden.requests.expand((r) => r).toSet(), hasLength(60));
    },
  );

  test(
    'stale append retains visible rows and rebuilds the requested extent',
    () async {
      final source = Source(65);
      final p = pager(source);
      addTearDown(p.dispose);
      await p.load();
      final original = p.transactions;
      source.wait = Completer<void>();
      source.invalidate = true;
      final loading = p.load(more: true);
      await Future<void>.delayed(Duration.zero);
      expect(p.isLoading, isTrue);
      expect(p.transactions, same(original));
      expect(p.visibleCount, 20);
      source.wait!.complete();
      await loading;
      expect(p.transactions!.first.txidHex, tx(999).txidHex);
      expect(p.transactions!.map((t) => t.txidHex).toSet(), hasLength(40));
      expect(p.visibleCount, 40);
      expect(source.indexReads, 2);
      expect(p.error, isNull);
    },
  );

  test('large refresh retains the previously visible rows', () async {
    final source = Source(65);
    final p = pager(source);
    addTearDown(p.dispose);
    await p.load();
    final prior = p.transactions!.map((t) => t.txidHex).toSet();
    source.transactions.insertAll(0, List.generate(30, (i) => tx(100 + i)));
    source.version++;
    await p.load(refresh: true);
    expect(p.visibleCount, 50);
    expect(
      p.transactions!
          .take(p.visibleCount)
          .map((t) => t.txidHex)
          .toSet()
          .containsAll(prior),
      isTrue,
    );
    expect(source.requests.every((r) => r.length <= 20), isTrue);
  });

  test('append failure preserves rows and retries the same page', () async {
    final source = Source(45);
    final p = pager(source);
    addTearDown(p.dispose);
    await p.load();
    source.fail = true;
    await p.load(more: true);
    expect(p.transactions, hasLength(20));
    expect(p.visibleCount, 20);
    expect(p.fresh, isFalse);
    expect(p.error, isNotNull);
    source.fail = false;
    await p.load(more: true);
    expect(p.transactions, source.transactions.take(40).toList());
    expect(p.visibleCount, 40);
    expect(p.fresh, isTrue);
    expect(p.error, isNull);
    expect(source.requests[1], source.requests[2]);
  });

  test(
    'retry restores an exhausted history after index refresh failure',
    () async {
      final source = Source(5);
      final p = pager(source);
      addTearDown(p.dispose);
      await p.load();
      expect(p.hasMore, isFalse);
      source.failIndex = true;
      await p.load(refresh: true);
      expect(p.error, isNotNull);
      source.failIndex = false;
      await p.retry();
      expect(p.error, isNull);
      expect(p.transactions, hasLength(5));
      expect(p.visibleCount, 20);
    },
  );

  test(
    'a buffered split-row page validates the DB snapshot before publication',
    () async {
      final source = Source(65)..splitAll = true;
      final p = pager(source);
      addTearDown(p.dispose);
      await p.load();
      expect(p.transactions, hasLength(40));
      source.transactions.insert(0, tx(999));
      source.version++;
      await p.load(more: true);
      expect(source.requests.any((r) => r.isEmpty), isTrue);
      expect(source.indexReads, 2);
      expect(p.transactions!.first.txidHex, tx(999).txidHex);
      expect(p.visibleCount, 40);
    },
  );

  test(
    'business timestamps pull an old native transaction into the first page',
    () async {
      final source = Source(65);
      final older = source.transactions.last;
      final p = pager(
        source,
        gifts: GiftCardActivityIndex(
          redeemedTxids: {older.txidHex},
          redeemedMetadataByTxid: {
            older.txidHex: GiftCardActivityMetadata(
              kind: GiftCardActivityKind.redeemed,
              amountZatoshi: BigInt.from(100),
              artworkId: null,
              message: null,
              activityTimestamp: DateTime.fromMillisecondsSinceEpoch(200000000),
            ),
          },
        ),
      );
      addTearDown(p.dispose);
      await p.load();
      expect(p.transactions!.any((t) => t.txidHex == older.txidHex), isTrue);
      expect(source.requests.first.first, older.txidHex);
      expect(p.transactions!.length, lessThan(65));
    },
  );

  test('dispose discards late native results', () async {
    final source = Source(25)..wait = Completer<void>();
    final p = pager(source);
    final loading = p.load();
    await Future<void>.delayed(Duration.zero);
    p.dispose();
    source.wait!.complete();
    await loading;
    expect(p.transactions, isNull);
  });
}
