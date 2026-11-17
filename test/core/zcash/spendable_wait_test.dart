import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/core/zcash/spendable_wait.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../support/test_l10n.dart';

const _tip = 1000;
const _nu7 = BlockSpacing(
  preNu7BlockSeconds: 75,
  nu7BlockSeconds: 25,
  nu7ActivationHeight: 1,
);
final _zec = BigInt.from(100000000);

void main() {
  test('a wait is a minute range around the target block time', () {
    expect(AvailableIn.fromSeconds(25), const AvailableIn.underMinute());
    expect(AvailableIn.fromSeconds(75), const AvailableIn.minutes(1, 2));
    expect(AvailableIn.fromSeconds(125), const AvailableIn.minutes(1, 3));
    expect(AvailableIn.fromSeconds(450), const AvailableIn.minutes(6, 8));
  });

  test('labels state the range or under a minute', () {
    expect(
      availableInLabel(testL10n, const AvailableIn.minutes(1, 3)),
      'Available in 1–3 min',
    );
    expect(
      availableInLabel(testL10n, const AvailableIn.underMinute()),
      'Available in under 1 min',
    );
  });

  group('spendableWaitOf', () {
    SpendableWait of(
      List<rust_sync.PendingSpendableEntry> entries, {
      int scannedHeight = _tip,
    }) => spendableWaitOf(
      availableNow: _zec,
      pending: PendingSpendable(tipHeight: _tip, entries: entries),
      scannedHeight: scannedHeight,
      spacing: _nu7,
    );

    test('nothing waiting has no wait', () {
      final wait = of(const []);
      expect(wait.availableNow, _zec);
      expect(wait.hasWait, isFalse);
      expect(wait.wait, isNull);
      expect(wait.waitFor(_zec + BigInt.one), isNull);
    });

    test('sums each cause and waits for its last transaction', () {
      final wait = of([
        _entry('a', blocks: 5),
        _entry('b', blocks: 2),
        _entry('c', isChange: true, blocks: 3),
        _entry('d', isChange: true, blocks: 1),
      ]);
      expect(wait.receivedWaiting, _zec * BigInt.two);
      expect(wait.receivedWait, const AvailableIn.minutes(1, 3));
      expect(wait.changeWaiting, _zec * BigInt.two);
      expect(wait.changeWait, const AvailableIn.minutes(1, 2));
      expect(wait.wait, const AvailableIn.minutes(1, 3));
      expect(wait.total, _zec * BigInt.from(5));
    });

    test('each block scanned since the read is one fewer to wait', () {
      final entries = [
        _entry('a', blocks: 5),
        _entry('c', isChange: true, blocks: 2),
      ];
      expect(
        of(entries, scannedHeight: _tip + 1).receivedWait,
        const AvailableIn.minutes(1, 2),
      );
      expect(
        of(entries, scannedHeight: _tip + 3).changeWait,
        const AvailableIn.underMinute(),
      );
      // Past its last block the amount is still listed, about to be read
      // as spendable.
      final past = of(entries, scannedHeight: _tip + 10);
      expect(past.waiting, _zec * BigInt.two);
      expect(past.wait, const AvailableIn.underMinute());
    });

    test('an unmined entry waits as read whatever is scanned', () {
      final wait = of([
        _entry('a', blocks: 6, confirmations: 0),
      ], scannedHeight: _tip + 4);
      expect(wait.receivedWait, const AvailableIn.minutes(1, 3));
    });

    test('an amount waits only for the transactions that cover it', () {
      final wait = spendableWaitOf(
        availableNow: BigInt.zero,
        pending: PendingSpendable(
          tipHeight: _tip,
          entries: [_entry('late', blocks: 5), _entry('soon', blocks: 1)],
        ),
        scannedHeight: _tip,
        spacing: _nu7,
      );
      // The cause as a whole waits for its last receipt.
      expect(wait.receivedWait, const AvailableIn.minutes(1, 3));
      // Half of the first receipt needs only that one.
      expect(wait.waitFor(_zec ~/ BigInt.two), const AvailableIn.underMinute());
      expect(wait.waitFor(_zec), const AvailableIn.underMinute());
      expect(wait.waitFor(_zec + BigInt.one), const AvailableIn.minutes(1, 3));
    });

    test('blocks are timed at the spacing of the tip', () {
      SpendableWait at(BlockSpacing spacing) => spendableWaitOf(
        availableNow: _zec,
        pending: PendingSpendable(
          tipHeight: _tip,
          entries: [_entry('a', blocks: 5)],
        ),
        scannedHeight: _tip,
        spacing: spacing,
      );
      expect(at(_nu7).receivedWait, const AvailableIn.minutes(1, 3));
      expect(
        at(
          const BlockSpacing(
            preNu7BlockSeconds: 75,
            nu7BlockSeconds: 25,
            nu7ActivationHeight: _tip * 2,
          ),
        ).receivedWait,
        const AvailableIn.minutes(5, 7),
      );
    });
  });

  group('waitFor', () {
    final wait = SpendableWait(
      availableNow: _zec,
      changeWaiting: _zec,
      receivedWaiting: _zec,
      changeWait: const AvailableIn.minutes(1, 2),
      receivedWait: const AvailableIn.minutes(1, 3),
    );

    test('an amount that fits now does not wait', () {
      expect(wait.waitFor(_zec), isNull);
    });

    test('states the earliest wait that covers the amount', () {
      expect(wait.waitFor(_zec + BigInt.one), const AvailableIn.minutes(1, 2));
      expect(
        wait.waitFor(_zec * BigInt.two + BigInt.one),
        const AvailableIn.minutes(1, 3),
      );
    });

    test('an amount the whole balance cannot cover does not wait', () {
      expect(wait.waitFor(_zec * BigInt.from(3) + BigInt.one), isNull);
      expect(wait.waitFor(_zec * BigInt.from(4)), isNull);
    });

    test('an amount without its fee keeps a reserve for it', () {
      final whole = _zec * BigInt.from(3);
      expect(wait.waitFor(whole), const AvailableIn.minutes(1, 3));
      expect(wait.waitFor(whole, includesFee: false), isNull);
      expect(
        wait.waitFor(whole - kSpendableWaitFeeReserve, includesFee: false),
        const AvailableIn.minutes(1, 3),
      );
      // Within a fee of what is spendable now: the fee has to wait too.
      expect(
        wait.waitFor(_zec, includesFee: false),
        const AvailableIn.minutes(1, 2),
      );
    });
  });

  group('receivedSpendableWaits', () {
    final pending = PendingSpendable(
      tipHeight: _tip,
      entries: [
        _entry('mined', blocks: 4, confirmations: 2),
        _entry('mempool', blocks: 6, confirmations: 0),
        _entry('change', isChange: true, blocks: 2, confirmations: 1),
      ],
    );
    final waits = receivedSpendableWaits(
      pending: pending,
      scannedHeight: _tip,
      spacing: _nu7,
    );

    test('blocks scanned since the read count as confirmations', () {
      ReceivedSpendableWait at(int scannedHeight) => receivedSpendableWaits(
        pending: pending,
        scannedHeight: scannedHeight,
        spacing: _nu7,
      )['mined']!;
      expect(at(_tip + 1).confirmations, 3);
      expect(at(_tip + 1).wait, const AvailableIn.minutes(1, 2));
      expect(at(_tip + 3).confirmations, 5);
      expect(at(_tip + 3).wait, const AvailableIn.underMinute());
      expect(at(_tip + 10).confirmations, 6);
      expect(at(_tip + 10).requiredConfirmations, 6);
      expect(at(_tip + 10).wait, const AvailableIn.underMinute());
      // A wallet still scanning up to the read's tip takes nothing back.
      expect(at(_tip - 1).confirmations, 2);
    });

    test('a mined receipt reports its wait and confirmations', () {
      expect(waits.keys, ['mined']);
      expect(waits['mined']!.wait, const AvailableIn.minutes(1, 2));
      expect(waits['mined']!.confirmations, 2);
      expect(waits['mined']!.requiredConfirmations, 6);
    });

    test('only a receipt row reads it', () {
      expect(
        receivedSpendableWaitFor(_tx('received', 'mined'), waits),
        isNotNull,
      );
      expect(receivedSpendableWaitFor(_tx('sent', 'mined'), waits), isNull);
      expect(receivedSpendableWaitFor(_tx('received', 'other'), waits), isNull);
    });
  });
}

rust_sync.PendingSpendableEntry _entry(
  String txid, {
  bool isChange = false,
  required int blocks,
  int confirmations = 1,
}) => rust_sync.PendingSpendableEntry(
  txidHex: txid,
  isChange: isChange,
  value: _zec,
  blocksUntilSpendable: blocks,
  confirmations: confirmations,
);

rust_sync.TransactionInfo _tx(String kind, String txid) {
  return rust_sync.TransactionInfo(
    txidHex: txid,
    minedHeight: BigInt.from(_tip),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    feeState: rust_sync.TransactionFeeState.notApplicable,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: kind,
    displayAmount: _zec,
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
