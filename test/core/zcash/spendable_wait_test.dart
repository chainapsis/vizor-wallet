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
  group('blocksUntilSpendable', () {
    test('a receipt is spendable on its sixth confirmation', () {
      int? blocks(int tip) => blocksUntilSpendable(
        minedHeight: 100,
        tipHeight: tip,
        requiredConfirmations: kReceivedSpendableConfirmations,
      );
      expect(blocks(100), 5);
      expect(blocks(104), 1);
      expect(blocks(105), 0);
      expect(blocks(200), 0);
    });

    test('change is spendable on its third confirmation', () {
      int? blocks(int tip) => blocksUntilSpendable(
        minedHeight: 100,
        tipHeight: tip,
        requiredConfirmations: kChangeSpendableConfirmations,
      );
      expect(blocks(100), 2);
      expect(blocks(102), 0);
    });

    test('an unmined output needs every confirmation', () {
      expect(
        blocksUntilSpendable(
          minedHeight: 0,
          tipHeight: _tip,
          requiredConfirmations: kChangeSpendableConfirmations,
        ),
        3,
      );
    });

    test('says nothing while the tip is unknown', () {
      expect(
        blocksUntilSpendable(
          minedHeight: 100,
          tipHeight: 0,
          requiredConfirmations: kReceivedSpendableConfirmations,
        ),
        isNull,
      );
    });
  });

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

  group('resolveSpendableWait', () {
    // [received] is the pending shielded value that is not pending change.
    SpendableWait? resolve({
      BigInt? change,
      BigInt? received,
      List<rust_sync.TransactionInfo> transactions = const [],
      bool catchingUp = false,
    }) {
      final c = change ?? BigInt.zero;
      return resolveSpendableWait(
        availableNow: _zec,
        shieldedPending: c + (received ?? BigInt.zero),
        changePending: c,
        tipHeight: _tip,
        spacing: _nu7,
        transactions: transactions,
        catchingUp: catchingUp,
      );
    }

    test('nothing pending has no wait', () {
      final wait = resolve()!;
      expect(wait.hasWait, isFalse);
      expect(wait.total, _zec);
    });

    test('a receipt just mined waits five more blocks', () {
      final wait = resolve(
        received: _zec,
        transactions: [_tx('received', minedHeight: _tip)],
      )!;
      expect(wait.receivedWaiting, _zec);
      expect(wait.receivedWait, const AvailableIn.minutes(1, 3));
      expect(wait.wait, const AvailableIn.minutes(1, 3));
    });

    test('change from a payment not yet mined waits three blocks', () {
      final wait = resolve(change: _zec, transactions: [_tx('sent')])!;
      expect(wait.changeWait, const AvailableIn.minutes(1, 2));
    });

    test('the whole wait is the later of the two causes', () {
      final wait = resolve(
        change: _zec,
        received: _zec,
        transactions: [
          _tx('sent', minedHeight: _tip),
          _tx('received', minedHeight: _tip),
        ],
      )!;
      expect(wait.changeWait, const AvailableIn.underMinute());
      expect(wait.wait, const AvailableIn.minutes(1, 3));
    });

    test('states no time without a transaction that explains the wait', () {
      final wait = resolve(received: _zec, transactions: [_tx('sent')])!;
      expect(wait.receivedWait, isNull);
      expect(wait.hasWait, isFalse);
      expect(wait.waitFor(_zec + BigInt.one), isNull);
    });

    test('ignores expired, transparent and already spendable entries', () {
      final wait = resolve(
        received: _zec,
        transactions: [
          _tx('received', minedHeight: _tip, expiredUnmined: true),
          _tx('received', minedHeight: _tip, isTransparent: true),
          _tx('received', minedHeight: _tip - 10),
        ],
      )!;
      expect(wait.receivedWait, isNull);
    });

    test('a receipt the unscanned tip just completed still waits a moment '
        'while catching up', () {
      final justCompleted = [_tx('received', minedHeight: _tip - 5)];
      expect(
        resolve(
          received: _zec,
          transactions: justCompleted,
          catchingUp: true,
        )!.receivedWait,
        const AvailableIn.underMinute(),
      );
      expect(
        resolve(received: _zec, transactions: justCompleted)!.receivedWait,
        isNull,
      );
      expect(
        resolve(
          received: _zec,
          transactions: [_tx('received', minedHeight: _tip - 9)],
          catchingUp: true,
        )!.receivedWait,
        isNull,
      );
    });

    test('change on its second confirmation, reported as pending value, '
        'still reads as change', () {
      // The wallet stops counting change as pending change one block before
      // the anchor reaches it; for that block it is pending value.
      final wait = resolve(
        received: _zec,
        transactions: [
          _tx('sent', minedHeight: _tip - 1),
          _old,
        ],
      )!;
      expect(wait.changeWaiting, _zec);
      expect(wait.receivedWaiting, BigInt.zero);
      expect(wait.changeWait, const AvailableIn.underMinute());
      expect(wait.hasWait, isTrue);
    });

    test('a list of nothing but recent entries cannot rule out a receipt', () {
      // The receipt behind the pending value may have been pushed out of the
      // newest-few list, so it is not read as change, and no wait is stated.
      final wait = resolve(
        received: _zec,
        transactions: [
          _tx('sent', minedHeight: _tip - 1),
          _tx('sent', minedHeight: _tip - 3),
        ],
      )!;
      expect(wait.changeWaiting, BigInt.zero);
      expect(wait.receivedWaiting, _zec);
      expect(wait.hasWait, isFalse);
    });

    test('a memo-only receipt explains no pending value', () {
      final memoOnly = _tx('received', minedHeight: _tip, amount: BigInt.zero);
      final wait = resolve(
        received: _zec,
        transactions: [
          memoOnly,
          _tx('received', minedHeight: _tip - 3),
        ],
      )!;
      // The older receipt's two remaining blocks, not the memo's five.
      expect(wait.receivedWait, const AvailableIn.underMinute());
      expect(
        resolve(received: _zec, transactions: [memoOnly])!.receivedWait,
        isNull,
      );
      expect(
        receivedSpendableWait(memoOnly, (
          tipHeight: _tip,
          spacing: _nu7,
          catchingUp: false,
        )),
        isNull,
      );
    });

    test('pending value is received funds while a receipt is waiting', () {
      final wait = resolve(
        received: _zec * BigInt.two,
        transactions: [
          _tx('sent', minedHeight: _tip - 1),
          _tx('received', minedHeight: _tip),
        ],
      )!;
      expect(wait.changeWaiting, BigInt.zero);
      expect(wait.receivedWaiting, _zec * BigInt.two);
      expect(wait.receivedWait, const AvailableIn.minutes(1, 3));
    });

    test('pending value no payment or receipt explains has no wait', () {
      final wait = resolve(
        received: _zec,
        transactions: [_tx('sent', minedHeight: _tip)],
      )!;
      expect(wait.receivedWaiting, _zec);
      expect(wait.hasWait, isFalse);
    });

    test('one payment on its second confirmation is found among newer '
        'ones', () {
      // The newer payment's change is still pending change; the older one's
      // has moved to pending value.
      final wait = resolve(
        change: _zec,
        received: _zec,
        transactions: [
          _tx('sent'),
          _tx('sent', minedHeight: _tip - 1),
          _old,
        ],
      )!;
      expect(wait.changeWaiting, _zec * BigInt.two);
      expect(wait.receivedWaiting, BigInt.zero);
      expect(wait.changeWait, const AvailableIn.minutes(1, 2));
      expect(wait.hasWait, isTrue);
    });

    test('several blocks landing in one catch-up do not drop the wait', () {
      final wait = resolve(
        received: _zec,
        transactions: [_tx('received', minedHeight: _tip - 7)],
        catchingUp: true,
      )!;
      expect(wait.receivedWait, const AvailableIn.underMinute());
      expect(
        resolve(
          received: _zec,
          transactions: [_tx('received', minedHeight: _tip - 20)],
          catchingUp: true,
        )!.receivedWait,
        isNull,
      );
    });

    test('more pending change than pending shielded value is unknown', () {
      expect(
        resolveSpendableWait(
          availableNow: _zec,
          shieldedPending: _zec,
          changePending: _zec * BigInt.two,
          tipHeight: _tip,
          spacing: _nu7,
          transactions: const [],
        ),
        isNull,
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

  test('a mined shielded receipt reports its wait and confirmations', () {
    const clock = (tipHeight: _tip, spacing: _nu7, catchingUp: false);
    final waiting = receivedSpendableWait(
      _tx('received', minedHeight: _tip - 1),
      clock,
    )!;
    expect(waiting.confirmations, 2);
    expect(waiting.wait, const AvailableIn.minutes(1, 2));
    expect(
      receivedSpendableWait(_tx('received', minedHeight: _tip - 5), clock),
      isNull,
    );
    expect(receivedSpendableWait(_tx('received'), clock), isNull);
    expect(
      receivedSpendableWait(_tx('sent', minedHeight: _tip), clock),
      isNull,
    );
  });
}

/// An entry old enough to spend: the list reaches back past the wait.
final _old = _tx('received', minedHeight: _tip - 50);

rust_sync.TransactionInfo _tx(
  String kind, {
  int minedHeight = 0,
  bool expiredUnmined = false,
  bool isTransparent = false,
  BigInt? amount,
}) {
  return rust_sync.TransactionInfo(
    txidHex: '$kind-$minedHeight',
    minedHeight: BigInt.from(minedHeight),
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    feeState: rust_sync.TransactionFeeState.notApplicable,
    detailsComplete: true,
    provisional: false,
    amountIncludesFee: false,
    blockTime: BigInt.from(1800000000),
    isTransparent: isTransparent,
    txKind: kind,
    displayAmount: amount ?? _zec,
    displayPool: isTransparent ? 'transparent' : 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
