import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/services/send_compose_dependencies.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_amount_suggestion.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  Future<SendAmountQuote> quote({
    bool ledger = true,
    Object? failure,
    BigInt? maxAmount,
    void Function()? onMax,
  }) => estimateSendAmountQuote(
    isLedger: ledger,
    dbPath: 'wallet',
    network: 'main',
    accountUuid: 'ledger-account',
    toAddress: 'recipient',
    amountZatoshi: BigInt.from(200000000),
    memo: 'unchanged memo',
    estimateFee:
        ({
          required dbPath,
          required network,
          required accountUuid,
          required toAddress,
          required amountZatoshi,
          memo,
        }) async {
          if (failure != null) throw failure;
          return BigInt.from(10000);
        },
    estimateMax:
        ({
          required dbPath,
          required network,
          required accountUuid,
          required toAddress,
          memo,
        }) async {
          onMax?.call();
          expect(accountUuid, 'ledger-account');
          expect(toAddress, 'recipient');
          expect(memo, 'unchanged memo');
          return rust_sync.SendMaxEstimateResult(
            amountZatoshi: maxAmount ?? BigInt.from(124000001),
            feeZatoshi: BigInt.from(15000),
            needsSaplingParams: false,
          );
        },
  );

  test('a feasible entered amount never requests a smaller amount', () async {
    final result = await quote(onMax: () => fail('No max needed'));
    expect(result, (fee: BigInt.from(10000), suggestedAmount: null));
  });

  test(
    'only capacity failure requests a destination-specific verified max',
    () async {
      var calls = 0;
      final result = await quote(
        failure: StateError('VIZOR_LEDGER_CAPACITY: limit'),
        onMax: () => calls++,
      );
      expect(result.suggestedAmount, BigInt.from(124000001));
      expect(result.fee, BigInt.from(15000));
      expect(calls, 1);
    },
  );

  for (final failure in [
    'network unavailable',
    'InsufficientFunds',
    'Ledger supports at most 1 BIP32 derivation per transparent output',
  ]) {
    test('does not rewrite the amount for $failure', () async {
      await expectLater(
        quote(failure: failure, onMax: () => fail('Not a capacity error')),
        throwsA(failure),
      );
    });
  }

  test(
    'software and Keystone do not adopt the Ledger correction path',
    () async {
      const failure = 'VIZOR_LEDGER_CAPACITY: limit';
      await expectLater(
        quote(ledger: false, failure: failure, onMax: () => fail('Not Ledger')),
        throwsA(failure),
      );
    },
  );

  for (final value in [0, 200000000, 300000000]) {
    test('does not suggest a zero or stale larger amount ($value)', () async {
      await expectLater(
        quote(
          failure: 'VIZOR_LEDGER_CAPACITY: limit',
          maxAmount: BigInt.from(value),
        ),
        throwsStateError,
      );
    });
  }

  test('the suggested amount preserves every zatoshi', () {
    expect(
      SendAmountSuggestion(amountZatoshi: BigInt.from(124000001)).amountText,
      '1.24000001',
    );
  });
}
