import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/payment_request_intake.dart';
import 'package:zcash_wallet/src/core/payments/cross_chain_payment_request.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';
import 'package:zcash_wallet/src/features/pay/providers/cross_chain_payment_request_provider.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';

void main() {
  ProviderContainer containerFor(CrossChainPaymentParser parser) {
    final container = ProviderContainer(
      overrides: [crossChainPaymentParserProvider.overrideWithValue(parser)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a slow older parse cannot replace a newer accepted request', () async {
    final older = _request('older');
    final newer = _request('newer', solana: true);
    final olderParse = Completer<CrossChainPaymentRequest>();
    final newerParse = Completer<CrossChainPaymentRequest>();
    final received = <String>[];
    final container = containerFor((raw) {
      received.add(raw);
      return raw == older.rawUri ? olderParse.future : newerParse.future;
    });
    final intake = container.read(paymentRequestIntakeProvider);

    final pendingOlder = intake.receive('  ${older.rawUri}  ');
    final pendingNewer = intake.receive(newer.rawUri);
    newerParse.complete(newer);

    expect(await pendingNewer, isFalse);
    expect(container.read(paymentUriPrefillProvider), same(newer));
    expect(container.read(paymentRequestArrivalProvider), 1);

    olderParse.complete(older);
    expect(await pendingOlder, isFalse);
    expect(container.read(paymentUriPrefillProvider), same(newer));
    expect(container.read(paymentRequestArrivalProvider), 1);
    expect(received, [older.rawUri, newer.rawUri]);
  });

  test(
    'an invalid new request preserves the park and supersedes old work',
    () async {
      final parked = _request('parked');
      final older = _request('older');
      final olderParse = Completer<CrossChainPaymentRequest>();
      final container = containerFor((raw) {
        if (raw == parked.rawUri) return Future.value(parked);
        if (raw == older.rawUri) return olderParse.future;
        return Future.error(const CrossChainPaymentParseException());
      });
      final intake = container.read(paymentRequestIntakeProvider);
      await intake.receive(parked.rawUri);
      final pendingOlder = intake.receive(older.rawUri);

      await expectLater(
        intake.receive('bitcoin:invalid-new-request'),
        throwsA(isA<CrossChainPaymentParseException>()),
      );
      expect(container.read(paymentUriPrefillProvider), same(parked));
      expect(container.read(paymentRequestArrivalProvider), 1);

      // Even a late error from the superseded parse must not become a new error
      // on the input surface after the latest request was already rejected.
      olderParse.completeError(const CrossChainPaymentParseException());
      expect(await pendingOlder, isFalse);
      expect(container.read(paymentUriPrefillProvider), same(parked));
      expect(container.read(paymentRequestArrivalProvider), 1);
    },
  );

  test(
    'reset invalidation prevents an in-flight parse from re-parking',
    () async {
      final beforeReset = _request('before-reset');
      final afterReset = _request('after-reset');
      final pendingParse = Completer<CrossChainPaymentRequest>();
      final container = containerFor((raw) {
        return raw == beforeReset.rawUri
            ? pendingParse.future
            : Future.value(afterReset);
      });
      final intake = container.read(paymentRequestIntakeProvider);
      final pending = intake.receive(beforeReset.rawUri);

      intake.invalidate();
      container.read(paymentUriPrefillProvider.notifier).clear();
      pendingParse.complete(beforeReset);

      expect(await pending, isFalse);
      expect(container.read(paymentUriPrefillProvider), isNull);
      expect(container.read(paymentRequestArrivalProvider), 0);

      expect(await intake.receive(afterReset.rawUri), isFalse);
      expect(container.read(paymentUriPrefillProvider), same(afterReset));
      expect(container.read(paymentRequestArrivalProvider), 1);
    },
  );

  test(
    'provider disposal invalidates a parse before it can read disposed state',
    () async {
      final request = _request('during-dispose');
      final parser = Completer<CrossChainPaymentRequest>();
      final container = ProviderContainer(
        overrides: [
          crossChainPaymentParserProvider.overrideWithValue(
            (_) => parser.future,
          ),
        ],
      );
      final pending = container
          .read(paymentRequestIntakeProvider)
          .receive(request.rawUri);

      container.dispose();
      parser.complete(request);

      expect(await pending, isFalse);
    },
  );

  test(
    'cross-chain parking keeps identity, replacement, and expiry semantics',
    () async {
      final first = _request('first');
      final second = _request('second', solana: true);
      final container = containerFor(
        (raw) => Future.value(raw == first.rawUri ? first : second),
      );
      final intake = container.read(paymentRequestIntakeProvider);
      final park = container.read(paymentUriPrefillProvider.notifier);

      expect(await intake.receive(first.rawUri), isFalse);
      expect(await intake.receive(second.rawUri), isTrue);
      final fresh = park.takeIfFresh();
      expect(fresh.prefill, same(second));
      expect(fresh.expired, isFalse);
      expect(container.read(paymentUriPrefillProvider), isNull);

      expect(await intake.receive(first.rawUri), isFalse);
      park.debugAgePark(
        PaymentUriPrefillNotifier.parkTtl + const Duration(seconds: 1),
      );
      final stale = park.takeIfFresh();
      expect(stale.prefill, isNull);
      expect(stale.expired, isTrue);
      expect(container.read(paymentUriPrefillProvider), isNull);
      expect(park.takeIfFresh().expired, isFalse);
      expect(container.read(paymentRequestArrivalProvider), 3);
    },
  );

  test(
    'generic URI detection retains Zcash and rejects unrelated inputs',
    () async {
      for (final uri in [
        'zcash:u1recipient',
        'bitcoin:recipient',
        'litecoin:recipient',
        '  ETHEREUM:recipient  ',
        'solana:recipient',
      ]) {
        expect(isPaymentRequestUri(uri), isTrue, reason: uri);
      }
      for (final input in [
        'u1recipient',
        '0x1111111111111111111111111111111111111111',
        'https://example.com/request',
        'lightning:invoice',
        'bitcoin-cash:recipient',
        '',
      ]) {
        expect(isPaymentRequestUri(input), isFalse, reason: input);
      }

      var crossChainParses = 0;
      final container = containerFor((_) {
        crossChainParses++;
        return Future.error(StateError('Zcash must use its existing parser'));
      });
      final intake = container.read(paymentRequestIntakeProvider);
      expect(await intake.receive(' ZCASH:u1recipient?amount=0.25 '), isFalse);
      final parked = container.read(paymentUriPrefillProvider);
      expect(parked, isA<SendPrefillArgs>());
      final zcashPrefill = parked! as SendPrefillArgs;
      expect(zcashPrefill.address, 'u1recipient');
      expect(zcashPrefill.amountText, '0.25');

      await expectLater(
        intake.receive('https://example.com/request'),
        throwsA(isA<Zip321ParseException>()),
      );
      expect(container.read(paymentUriPrefillProvider), same(parked));
      expect(container.read(paymentRequestArrivalProvider), 1);
      expect(crossChainParses, 0);
    },
  );
}

CrossChainPaymentRequest _request(String id, {bool solana = false}) {
  final address = solana
      ? 'mvines9iiHiQTysrwkJjGf2gb9Ex9jXJX8ns3qwf2kN'
      : '1FsSia9rv4NeEwvJ2GvXrX7LyxYspbN2mo';
  return CrossChainPaymentRequest(
    id: id,
    rawUri: '${solana ? 'solana' : 'bitcoin'}:$address?label=$id',
    address: address,
    isEvm: false,
    chain: solana ? 'sol' : 'btc',
  );
}
