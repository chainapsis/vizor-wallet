import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_receive_reservation_service.dart';
import 'package:zcash_wallet/src/rust/api/dynamic_ivk.dart' as api;

void main() {
  late _Store store;
  late SwapReceiveReservationService service;
  setUp(() {
    store = _Store();
    service = SwapReceiveReservationService(store: (_) async => store);
  });

  test(
    'persists unknown request just before contacting provider and saves response',
    () async {
      final quote = await service.quote('account', BigInt.one, (
        beforeSend,
      ) async {
        // Local validation and token lookups happen before anything is saved.
        expect(store.events, isEmpty);
        await beforeSend(_deadline);
        expect(store.events, ['begin']);
        store.events.add('network');
        return _quote;
      });
      expect(quote.receiveRequestId, 'request-1');
      expect(quote.depositInstruction, same(_quote.depositInstruction));
      expect(store.events, ['begin', 'network', 'accept:request-1']);
      expect(store.deadlines, [_deadline]);
    },
  );

  test(
    'explicit amount rejection releases its watch but timeout stays unknown',
    () async {
      await expectLater(
        service.quote('account', BigInt.one, (beforeSend) async {
          await beforeSend(_deadline);
          throw const OneClickApiException(
            'amount too low',
            operation: 'quote',
            statusCode: 400,
          );
        }),
        throwsA(isA<OneClickApiException>()),
      );
      expect(store.events, ['begin', 'reject:request-1']);
      store.events.clear();
      await expectLater(
        service.quote('account', BigInt.one, (beforeSend) async {
          await beforeSend(_deadline);
          throw TimeoutException('lost response');
        }),
        throwsA(isA<TimeoutException>()),
      );
      expect(store.events, ['begin']);
    },
  );

  test('a request that never leaves the device saves nothing', () async {
    await expectLater(
      service.quote('account', BigInt.one, (_) async {
        throw const OneClickApiException(
          'Quote amount text is required',
          operation: 'quote',
        );
      }),
      throwsA(isA<OneClickApiException>()),
    );
    await expectLater(
      service.quote('account', BigInt.one, (_) async => _quote),
      throwsA(isA<StateError>()),
    );
    expect(store.events, isEmpty);
  });

  test('starting a quote checks the deposit instructions it saved', () async {
    // A quote that never reserved an address has nothing to start.
    await service.start('account', _quote);
    expect(store.events, isEmpty);
    final quote = SwapQuote.withLocalIdentity(
      _quote,
      receiveRequestId: 'request-1',
    );
    await service.start('account', quote);
    expect(store.events, ['start:request-1']);
    store.savedMemo = 'other-memo';
    await expectLater(
      service.start('account', quote),
      throwsA(isA<StateError>()),
    );
  });

  test('reserves the address each direction quotes with', () async {
    for (final direction in SwapDirection.values) {
      await service.reserve('account', direction, BigInt.from(100));
    }
    expect(store.events, [
      for (final direction in SwapDirection.values)
        'reserve:${direction.sendsZec ? 'refund' : 'incoming'}',
    ]);
  });

  test('records a refund quote before returning it, if address-only', () async {
    final refund = await service.quoteRefund(
      'account',
      BigInt.from(7),
      () async => _refundQuote(),
    );
    expect(refund.swapRefundIndex, BigInt.from(7));
    expect(store.events, ['refund:7:t1deposit']);
    // The funding transaction cannot carry a deposit memo.
    await expectLater(
      service.quoteRefund(
        'account',
        BigInt.from(8),
        () async => _refundQuote(memo: 'memo'),
      ),
      throwsStateError,
    );
    expect(store.events, ['refund:7:t1deposit']);
  });

  test('forwards statuses for supported accounts only', () async {
    final checkedAt = DateTime.now().toUtc();
    for (final direction in SwapDirection.values) {
      await service.observeStatus(
        'account',
        direction: direction,
        depositAddress: 'deposit',
        memo: 'memo',
        snapshot: _snapshot,
        checkedAt: checkedAt,
      );
    }
    service = SwapReceiveReservationService(
      store: (_) async => store,
      supportsAccount: (_) => false,
    );
    await service.observeStatus(
      'hardware',
      direction: SwapDirection.zecToExternal,
      depositAddress: 'deposit',
      memo: null,
      snapshot: _snapshot,
      checkedAt: checkedAt,
    );
    expect(store.events, [
      for (final direction in SwapDirection.values)
        'observe:${direction.sendsZec ? 'refund' : 'incoming'}:deposit:memo',
    ]);
  });

  test(
    'wallet deletion waits for in-flight quote result persistence',
    () async {
      final lifecycle = LedgerOperationLifecycle();
      service = SwapReceiveReservationService(
        store: (_) async => store,
        lifecycle: lifecycle,
      );
      for (final refund in [false, true]) {
        store.events.clear();
        final contacted = Completer<void>();
        final result = Completer<SwapQuote>();
        final quote = refund
            ? service.quoteRefund('account', BigInt.from(7), () {
                contacted.complete();
                return result.future;
              })
            : service.quote('account', BigInt.one, (beforeSend) async {
                await beforeSend(_deadline);
                contacted.complete();
                return result.future;
              });
        await contacted.future;
        var drained = false;
        final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
        await Future<void>.delayed(Duration.zero);
        expect(drained, false);
        result.complete(refund ? _refundQuote() : _quote);
        await quote;
        await drain;
        expect(
          store.events,
          refund ? ['refund:7:t1deposit'] : ['begin', 'accept:request-1'],
        );
        expect(drained, true);
        lifecycle.resume();
      }
    },
  );
}

final _deadline = DateTime.utc(2026, 10);
final _quote = SwapQuote(
  direction: SwapDirection.externalToZec,
  sellAsset: SwapAsset.usdc,
  receiveAsset: SwapAsset.zec,
  externalAsset: SwapAsset.usdc,
  sellAmount: 5,
  receiveAmount: 0.01,
  minimumReceiveAmount: 0.009,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included',
  expiryLabel: '10:00',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.usdc,
    address: 'deposit',
    expiresInLabel: '10:00',
    reuseWarning: '',
    memo: 'memo',
    deadline: _deadline,
  ),
);
final _snapshot = SwapIntentSnapshot.fromQuote(_quote);

/// An address-only ZEC deposit quote, or one with `memo`.
SwapQuote _refundQuote({String? memo}) => SwapQuote(
  direction: SwapDirection.zecToExternal,
  sellAsset: SwapAsset.zec,
  receiveAsset: SwapAsset.usdc,
  externalAsset: SwapAsset.usdc,
  sellAmount: 1,
  receiveAmount: 70,
  minimumReceiveAmount: 69,
  providerLabel: 'NEAR Intents',
  feeLabel: 'Included',
  expiryLabel: '10:00',
  depositInstruction: SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 't1deposit',
    expiresInLabel: '10:00',
    reuseWarning: '',
    memo: memo,
    deadline: _deadline,
  ),
);

class _Store implements ReceiveReservationStore {
  final events = <String>[];
  final requests = <String>[];
  final deadlines = <DateTime>[];
  String savedMemo = 'memo';
  @override
  Future<api.SwapAddress> reserve({
    required bool incoming,
    required BigInt tip,
  }) async {
    events.add('reserve:${incoming ? 'incoming' : 'refund'}');
    return api.SwapAddress(
      address: 'u1test',
      refundIndex: incoming ? null : BigInt.one,
      reservationIndex: incoming ? BigInt.one : null,
    );
  }

  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async {
    events.add('begin');
    final request = 'request-${requests.length + 1}';
    requests.add(request);
    deadlines.add(deadline);
    return request;
  }

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {
    expect(requests, contains(request));
    events.add('${accepted == null ? 'reject' : 'accept'}:$request');
  }

  @override
  Future<api.ReceiveDeposit> start(String request) async {
    events.add('start:$request');
    return api.ReceiveDeposit(
      address: 'deposit',
      memo: savedMemo,
      deadlineSeconds: unixSeconds(_deadline),
    );
  }

  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) async {
    events.add('refund:$refundIndex:${quote.depositInstruction.address}');
  }

  @override
  Future<void> observe({
    required bool incoming,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  }) async {
    events.add(
      'observe:${incoming ? 'incoming' : 'refund'}:$depositAddress:$memo',
    );
  }
}
