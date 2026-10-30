import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_contract.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_receive_reservation_service.dart';
import 'package:zcash_wallet/src/rust/api/one_time_ivk.dart' as api;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  late _Store store;
  late SwapReceiveReservationService service;
  setUp(() {
    store = _Store();
    service = SwapReceiveReservationService(store: (_) async => store);
  });

  /// Quotes once, failing with `error` after the request left the device.
  Future<void> failSent(Object error) => expectLater(
    service.quote('account', BigInt.one, (beforeSend) async {
      await beforeSend(_deadline);
      throw error;
    }),
    throwsA(same(error)),
  );

  test('persists unknown request just before contacting provider and saves response', () async {
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
  });

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
    store
      ..savedMemo = 'memo'
      ..savedAddress = 'other';
    await expectLater(
      service.start('account', quote),
      throwsA(isA<StateError>()),
    );
  });

  /// Only 1Click's own validation refusal of a quote (400 or 422) proves no
  /// deposit instructions exist, so only it releases the reservation.
  for (final code in [400, 422]) {
    test('a quote refused with $code releases its reservation', () async {
      await failSent(
        OneClickApiException('bad', operation: 'quote', statusCode: code),
      );
      expect(store.events, ['begin', 'reject:request-1']);
    });
  }

  /// Everything else after sending may hide a quote NEAR issued: server
  /// errors, throttling, auth failures, a refusal of some other call,
  /// transport failures and malformed responses keep the slot held.
  final ambiguous = <String, Object>{
    '500': const OneClickApiException(
      'server',
      operation: 'quote',
      statusCode: 500,
    ),
    '429': const OneClickApiException(
      'slow down',
      operation: 'quote',
      statusCode: 429,
    ),
    '401': const OneClickApiException(
      'auth',
      operation: 'quote',
      statusCode: 401,
    ),
    'a 400 for another call': const OneClickApiException(
      'bad',
      operation: 'status',
      statusCode: 400,
    ),
    'a 400 without an operation': const OneClickApiException(
      'bad',
      statusCode: 400,
    ),
    'a dropped socket': const SocketException('reset'),
    'a malformed success': const FormatException('bad json'),
  };
  for (final MapEntry(key: name, value: error) in ambiguous.entries) {
    test('$name after sending keeps the reservation unresolved', () async {
      await failSent(error);
      expect(store.events, ['begin']);
    });
  }

  /// A quote the wallet could not save is not returned, so the UI never shows
  /// deposit instructions the wallet does not own.
  test('a quote whose acceptance fails to save is not shown', () async {
    store.finishError = StateError('database is locked');
    await expectLater(
      service.quote('account', BigInt.one, (beforeSend) async {
        await beforeSend(_deadline);
        return _quote;
      }),
      throwsStateError,
    );
    expect(store.events, ['begin']);
  });

  /// If saving the request fails, the send hook throws before anything leaves
  /// the device, and nothing is finished.
  test('a request the wallet could not begin is never finished', () async {
    store.beginError = const api.ReceiveError(
      message: 'This swap address is no longer available.',
      kind: api.ReceiveErrorKind.stale,
    );
    var sent = false;
    await expectLater(
      service.quote('account', BigInt.one, (beforeSend) async {
        await beforeSend(_deadline);
        sent = true;
        return _quote;
      }),
      throwsA(isA<api.ReceiveError>()),
    );
    expect(sent, isFalse);
    expect(store.events, isEmpty);
  });

  /// Funding requires the refund key's record, so a refund quote whose record
  /// fails is not returned.
  test('a refund quote is returned only once it is recorded', () async {
    store.refundError = StateError('database is locked');
    await expectLater(
      service.quoteRefund('account', BigInt.two, () async => _refundQuote()),
      throwsStateError,
    );
  });

  /// A start the wallet refuses, such as an address queued for another history
  /// check, surfaces the wallet's error unchanged so the app can explain it.
  test('a refused start keeps the wallet error', () async {
    store.startError = const api.ReceiveError(
      message: 'Preparing a private swap address. Try again in a moment.',
      kind: api.ReceiveErrorKind.receiveHistory,
    );
    final quote = SwapQuote.withLocalIdentity(
      _quote,
      receiveRequestId: 'request-1',
    );
    await expectLater(
      service.start('account', quote),
      throwsA(
        isA<api.ReceiveError>().having(
          (e) => e.kind,
          'kind',
          api.ReceiveErrorKind.receiveHistory,
        ),
      ),
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

  group('Rust store', () {
    late _Api rust;
    setUpAll(() {
      rust = _Api();
      RustLib.initMock(api: rust);
    });
    tearDownAll(RustLib.dispose);
    setUp(() {
      rust.observed.clear();
      rust.tracked = true;
    });

    /// The wallet gets the raw provider status, both transaction lists, the
    /// direction and whether NEAR saw a deposit, and its answer, whether it
    /// still tracks the address, comes back unchanged.
    test('observing a status forwards what the wallet needs', () async {
      const store = RustReceiveReservationStore('wallet.db', 'main', 'acct');
      final checkedAt = DateTime.utc(2026, 10, 22, 12);
      rust.tracked = false;
      final tracked = await store.observe(
        incoming: false,
        depositAddress: 't1deposit',
        memo: null,
        snapshot: _statusSnapshot(
          SwapIntentStatus.refunded,
          raw: 'REFUNDED',
          origin: ['zec-funding'],
          destination: ['zec-refund'],
          refundedBaseUnits: '1000',
        ),
        checkedAt: checkedAt,
      );
      expect(tracked.tracked, isFalse, reason: "Rust's answer is returned");
      final call = rust.observed.single;
      expect(call.incoming, isFalse);
      expect(call.depositAddress, 't1deposit');
      expect(call.status.status, 'REFUNDED');
      expect(call.status.refundedAmount, '1000');
      expect(call.status.originTxHashes, ['zec-funding']);
      expect(call.status.destinationTxHashes, ['zec-refund']);
      expect(call.funded, isTrue);
      expect(call.checkedAt.toInt(), checkedAt.millisecondsSinceEpoch ~/ 1000);
    });

    /// `funded` follows provider deposit evidence, and a status without a raw
    /// value is reported as UNKNOWN rather than guessed.
    test('funded follows the provider deposit evidence', () async {
      const store = RustReceiveReservationStore('wallet.db', 'main', 'acct');
      final cases = <(SwapIntentSnapshot, bool)>[
        (_statusSnapshot(SwapIntentStatus.awaitingExternalDeposit), false),
        (_statusSnapshot(SwapIntentStatus.depositObserved), true),
        (_statusSnapshot(SwapIntentStatus.incompleteDeposit), true),
        (_statusSnapshot(SwapIntentStatus.failed), false),
        (_statusSnapshot(SwapIntentStatus.failed, origin: ['tx']), true),
      ];
      for (final (snapshot, _) in cases) {
        await store.observe(
          incoming: true,
          depositAddress: '0xdeposit',
          memo: 'memo',
          snapshot: snapshot,
          checkedAt: DateTime.utc(2026),
        );
      }
      expect(rust.observed.map((c) => c.funded), [
        for (final (_, funded) in cases) funded,
      ]);
      expect(rust.observed.first.status.status, 'UNKNOWN');
      expect(rust.observed.first.memo, 'memo');
    });
  });
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

/// A provider status snapshot with `status`, and its raw value and
/// transaction lists when given.
SwapIntentSnapshot _statusSnapshot(
  SwapIntentStatus status, {
  String? raw,
  List<String> origin = const [],
  List<String> destination = const [],
  String? refundedBaseUnits,
}) => SwapIntentSnapshot(
  id: 'deposit',
  providerLabel: 'NEAR Intents',
  pairText: 'ZEC -> USDC',
  sellAmountText: '1 ZEC',
  receiveEstimateText: '70 USDC',
  status: status,
  nextAction: status.label,
  providerStatusRaw: raw,
  originChainTxHash: origin.isEmpty ? null : origin.first,
  originChainTxHashes: origin,
  destinationChainTxHashes: destination,
  refundedAmountBaseUnits: refundedBaseUnits,
  depositInstruction: const SwapDepositInstruction(
    asset: SwapAsset.zec,
    address: 'deposit',
    expiresInLabel: '10:00',
    reuseWarning: '',
  ),
);

/// Records calls in [events], failing a call whose error is set.
class _Store implements ReceiveReservationStore {
  final events = <String>[];
  final requests = <String>[];
  final deadlines = <DateTime>[];
  String savedMemo = 'memo';
  String savedAddress = 'deposit';
  Object? beginError;
  Object? finishError;
  Object? startError;
  Object? refundError;
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
    if (beginError case final error?) throw error;
    events.add('begin');
    final request = 'request-${requests.length + 1}';
    requests.add(request);
    deadlines.add(deadline);
    return request;
  }

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {
    expect(requests, contains(request));
    if (finishError case final error?) throw error;
    events.add('${accepted == null ? 'reject' : 'accept'}:$request');
  }

  @override
  Future<api.ReceiveDeposit> start(String request) async {
    if (startError case final error?) throw error;
    events.add('start:$request');
    return api.ReceiveDeposit(
      address: savedAddress,
      memo: savedMemo,
      deadlineSeconds: unixSeconds(_deadline),
    );
  }

  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) async {
    if (refundError case final error?) throw error;
    events.add('refund:$refundIndex:${quote.depositInstruction.address}');
  }

  @override
  Future<api.SwapStatusRecord> observe({
    required bool incoming,
    required String depositAddress,
    required String? memo,
    required SwapIntentSnapshot snapshot,
    required DateTime checkedAt,
  }) async {
    events.add(
      'observe:${incoming ? 'incoming' : 'refund'}:$depositAddress:$memo',
    );
    return const api.SwapStatusRecord(tracked: true, receiptExpected: false);
  }
}

/// One `observe_swap_status` call as Rust receives it.
typedef _Observed = ({
  bool incoming,
  String depositAddress,
  String? memo,
  api.SwapProviderStatus status,
  bool funded,
  PlatformInt64 checkedAt,
});

/// Rust with only the status observation, which records its arguments.
class _Api extends RustLibApi {
  final observed = <_Observed>[];

  /// What Rust answers: whether it still tracked the address.
  bool tracked = true;

  @override
  Future<api.SwapStatusRecord> crateApiOneTimeIvkObserveSwapStatus({
    required String dbPath,
    required String networkName,
    required String accountUuid,
    required bool incoming,
    required String depositAddress,
    String? depositMemo,
    required api.SwapProviderStatus status,
    required bool funded,
    required PlatformInt64 checkedAtSeconds,
  }) async {
    observed.add((
      incoming: incoming,
      depositAddress: depositAddress,
      memo: depositMemo,
      status: status,
      funded: funded,
      checkedAt: checkedAtSeconds,
    ));
    return api.SwapStatusRecord(tracked: tracked, receiptExpected: false);
  }

  /// Fails any Rust call this fake does not expect.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
