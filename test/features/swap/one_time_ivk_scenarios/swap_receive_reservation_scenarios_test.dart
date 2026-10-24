// Scenario tests for the quote lifecycle of one-time swap addresses: which
// quote failures release a reservation, and what the Rust-backed store hands
// the wallet. See `SwapReceiveReservationService` and
// docs/near-swap-receiving.md.
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
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
      service.quoteRefund('account', BigInt.two, () async => _refundQuote),
      throwsStateError,
    );
  });

  /// A start whose saved instructions differ from the quote's deposit address
  /// refuses, as a changed memo already does.
  test('a start refuses instructions saved for another address', () async {
    store.savedAddress = 'other';
    final quote = SwapQuote.withLocalIdentity(
      _quote,
      receiveRequestId: 'request-1',
    );
    await expectLater(service.start('account', quote), throwsStateError);
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
        snapshot: _snapshot(
          SwapIntentStatus.refunded,
          raw: 'REFUNDED',
          origin: ['zec-funding'],
          destination: ['zec-refund'],
          refundedBaseUnits: '1000',
        ),
        checkedAt: checkedAt,
      );
      expect(tracked, isFalse, reason: "Rust's answer is returned");
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
        (_snapshot(SwapIntentStatus.awaitingExternalDeposit), false),
        (_snapshot(SwapIntentStatus.depositObserved), true),
        (_snapshot(SwapIntentStatus.incompleteDeposit), true),
        (_snapshot(SwapIntentStatus.failed), false),
        (_snapshot(SwapIntentStatus.failed, origin: ['tx']), true),
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

final _refundQuote = SwapQuote(
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
    deadline: _deadline,
  ),
);

/// A provider status snapshot with `status`, and its raw value and
/// transaction lists when given.
SwapIntentSnapshot _snapshot(
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

/// Records calls in [events], failing a call whose error is set. Other calls
/// fail.
class _Store extends Fake implements ReceiveReservationStore {
  final events = <String>[];
  var _requests = 0;
  Object? beginError;
  Object? finishError;
  Object? startError;
  Object? refundError;
  String savedAddress = 'deposit';

  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async {
    if (beginError case final error?) throw error;
    events.add('begin');
    return 'request-${++_requests}';
  }

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {
    if (finishError case final error?) throw error;
    events.add('${accepted == null ? 'reject' : 'accept'}:$request');
  }

  @override
  Future<api.ReceiveDeposit> start(String request) async {
    if (startError case final error?) throw error;
    return api.ReceiveDeposit(
      address: savedAddress,
      memo: 'memo',
      deadlineSeconds: unixSeconds(_deadline),
    );
  }

  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) async {
    if (refundError case final error?) throw error;
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
  Future<bool> crateApiOneTimeIvkObserveSwapStatus({
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
    return tracked;
  }

  /// Fails any Rust call this fake does not expect.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
