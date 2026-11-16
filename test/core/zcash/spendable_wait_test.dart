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
    SpendableWait? resolve({
      BigInt? change,
      BigInt? received,
      BigInt? transparentPending,
      BigInt? shieldedPending,
      List<rust_sync.TransactionInfo> transactions = const [],
      bool catchingUp = false,
    }) {
      final c = change ?? BigInt.zero;
      final v = received ?? BigInt.zero;
      return resolveSpendableWait(
        availableNow: _zec,
        shieldedPending: shieldedPending ?? c + v,
        transparentPending: transparentPending ?? BigInt.zero,
        changePending: c,
        valuePending: v,
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
          transactions: [_tx('received', minedHeight: _tip - 6)],
          catchingUp: true,
        )!.receivedWait,
        isNull,
      );
    });

    test('pending transparent value is left out of the shielded split', () {
      // The causes are summed over every pool; change is shielded only, so
      // the transparent share comes out of the received value.
      final wait = resolve(
        change: _zec,
        received: _zec + BigInt.from(5000),
        shieldedPending: _zec * BigInt.two,
        transparentPending: BigInt.from(5000),
        transactions: [
          _tx('sent', minedHeight: _tip),
          _tx('received', minedHeight: _tip),
        ],
      )!;
      expect(wait.changeWaiting, _zec);
      expect(wait.receivedWaiting, _zec);
      expect(wait.hasWait, isTrue);
    });

    test('a split that does not add up is unknown', () {
      expect(
        resolve(received: _zec, shieldedPending: _zec * BigInt.two),
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

rust_sync.TransactionInfo _tx(
  String kind, {
  int minedHeight = 0,
  bool expiredUnmined = false,
  bool isTransparent = false,
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
    displayAmount: _zec,
    displayPool: isTransparent ? 'transparent' : 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}
