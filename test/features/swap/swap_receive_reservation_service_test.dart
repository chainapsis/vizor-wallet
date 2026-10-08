import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_receive_reservation_service.dart';
import 'package:zcash_wallet/src/rust/api/swap_receive.dart' as api;

void main() {
  late _Store store;
  late SwapReceiveReservationService service;
  setUp(() {
    store = _Store();
    service = SwapReceiveReservationService(store: (_) async => store);
  });

  test('persists unknown request just before contacting provider and saves response', () async {
    final quote = await service.quote('account', 1, (beforeSend) async {
      // Local validation and token lookups happen before anything is saved.
      expect(store.events, isEmpty);
      await beforeSend(_deadline);
      expect(store.events, ['begin']);
      store.events.add('network');
      return _quote;
    });
    expect(quote.receiveRequestId, 'request-1');
    expect(quote.depositInstruction, same(_quote.depositInstruction));
    expect(store.events, ['begin', 'network', 'record:request-1']);
    expect(store.deadlines, [_deadline]);
  });

  test(
    'explicit amount rejection releases its watch but timeout stays unknown',
    () async {
      await expectLater(
        service.quote('account', 1, (beforeSend) async {
          await beforeSend(_deadline);
          throw const OneClickApiException(
            'amount too low',
            operation: 'quote',
            statusCode: 400,
          );
        }),
        throwsA(isA<OneClickApiException>()),
      );
      expect(store.events, ['begin', 'reject']);
      store.events.clear();
      await expectLater(
        service.quote('account', 1, (beforeSend) async {
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
      service.quote('account', 1, (_) async {
        throw const OneClickApiException(
          'Quote amount text is required',
          operation: 'quote',
        );
      }),
      throwsA(isA<OneClickApiException>()),
    );
    await expectLater(
      service.quote('account', 1, (_) async => _quote),
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

  test('reconciling only reaps; statuses come from activity polls', () async {
    store.pending.add(
      const api.ReceiveQuoteStatusRequest(
        requestId: 'visible',
        operationId: 'deposit',
        depositMemo: 'memo',
      ),
    );
    await service.reconcile('account');
    expect(store.events, ['reap']);
    await service.observeStatus(
      'account',
      'deposit',
      'memo',
      _snapshot,
      DateTime.now().toUtc(),
    );
    expect(store.events, ['reap', 'observe:visible']);
  });

  test('records refund statuses only for supported accounts', () async {
    final checkedAt = DateTime.now().toUtc();
    await service.observeRefundStatus(
      'account',
      'deposit',
      'u1refund',
      _snapshot,
      checkedAt,
    );
    service = SwapReceiveReservationService(
      store: (_) async => store,
      supportsAccount: (_) => false,
    );
    await service.observeRefundStatus(
      'hardware',
      'deposit',
      'u1refund',
      _snapshot,
      checkedAt,
    );
    expect(store.events, ['refund:deposit:u1refund']);
  });

  test(
    'wallet deletion waits for in-flight quote result persistence',
    () async {
      final lifecycle = LedgerOperationLifecycle();
      service = SwapReceiveReservationService(
        store: (_) async => store,
        lifecycle: lifecycle,
      );
      final contacted = Completer<void>();
      final result = Completer<SwapQuote>();
      final quote = service.quote('account', 1, (beforeSend) async {
        await beforeSend(_deadline);
        contacted.complete();
        return result.future;
      });
      await contacted.future;
      var drained = false;
      final drain = lifecycle.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      result.complete(_quote);
      await quote;
      await drain;
      expect(store.events, ['begin', 'record:request-1']);
      expect(drained, true);
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

class _Store implements ReceiveReservationStore {
  final events = <String>[];
  final requests = <String>[];
  final deadlines = <DateTime>[];
  final pending = <api.ReceiveQuoteStatusRequest>[];
  String savedMemo = 'memo';
  @override
  Future<api.ReceiveReservation> prepare(BigInt tip) async =>
      const api.ReceiveReservation(id: 1, address: 'u1test');
  @override
  Future<String> begin(PlatformInt64 reservation, DateTime deadline) async {
    events.add('begin');
    final request = 'request-${requests.length + 1}';
    requests.add(request);
    deadlines.add(deadline);
    return request;
  }

  @override
  Future<void> record(String request, SwapQuote quote) async {
    expect(requests, contains(request));
    events.add('record:$request');
  }

  @override
  Future<void> reject(String request) async {
    events.add('reject');
  }

  @override
  Future<api.ReceiveDepositInstruction> start(String request) async {
    events.add('start:$request');
    return api.ReceiveDepositInstruction(address: 'deposit', memo: savedMemo);
  }

  @override
  Future<List<api.ReceiveQuoteStatusRequest>> due() async => List.of(pending);
  @override
  Future<void> observe(
    String request,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async {
    events.add('observe:$request');
    pending.removeWhere((q) => q.requestId == request);
  }

  @override
  Future<void> observeRefund(
    String operation,
    String refundAddress,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async {
    events.add('refund:$operation:$refundAddress');
  }

  @override
  Future<void> reap() async {
    events.add('reap');
  }
}
