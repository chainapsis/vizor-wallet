import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/models/send_scan_result.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

void main() {
  group('resolveSendScanPayload', () {
    test('a bare address scans as a recipient, with nothing lost', () {
      final result = resolveSendScanPayload(_address);
      expect(result, isA<SendScanAddress>());
      expect((result! as SendScanAddress).address, _address);
      expect((result as SendScanAddress).downgrade, isNull);
    });

    test('a ZIP-321 request with an amount becomes a payment request', () {
      final result = resolveSendScanPayload(
        'zcash:$_address?amount=0.25&label=Coffee%20shop&message=Table%204',
      );
      expect(result, isA<SendScanPaymentRequest>());
      final prefill = (result! as SendScanPaymentRequest).prefill;
      expect(prefill.source, kPaymentUriPrefillSource);
      expect(prefill.address, _address);
      expect(prefill.amountText, '0.25');
      expect(prefill.label, 'Coffee shop');
      expect(prefill.message, 'Table 4');
    });

    test('each scanned request gets its own prefill id', () {
      const raw = 'zcash:$_address?amount=0.25';
      final first = resolveSendScanPayload(raw)! as SendScanPaymentRequest;
      final second = resolveSendScanPayload(raw)! as SendScanPaymentRequest;
      expect(first.prefill.id, isNot(second.prefill.id));
    });

    test('an amount-less ZIP-321 request stays address-only', () {
      final result = resolveSendScanPayload(
        'zcash:$_address?message=Table%204',
      );
      expect(result, isA<SendScanAddress>());
      expect((result! as SendScanAddress).address, _address);
      expect(
        (result as SendScanAddress).downgrade,
        isNull,
        reason: 'the address is exactly what the request asked to be paid at',
      );
    });

    test('a zero amount stays address-only', () {
      final result = resolveSendScanPayload('zcash:$_address?amount=0');
      expect(result, isA<SendScanAddress>());
    });

    test('a request the parser refuses falls back to the scanned address', () {
      // Two payments: unsupported, so there is no single request to present.
      final result = resolveSendScanPayload(
        'zcash:?address=$_address&amount=0.25'
        '&address.1=$_address&amount.1=0.5',
        acceptedAddress: _address,
      );
      expect(result, isA<SendScanAddress>());
      expect((result! as SendScanAddress).address, _address);
      expect(
        (result as SendScanAddress).downgrade,
        SendScanDowngrade.multipleRecipients,
      );
    });

    test('the address the scanner validated wins over re-derivation', () {
      final result = resolveSendScanPayload(
        'not a uri at all',
        acceptedAddress: _address,
      );
      expect((result! as SendScanAddress).address, _address);
    });

    test('a payload with no address at all resolves to nothing', () {
      expect(resolveSendScanPayload('   '), isNull);
    });
  });

  // A refused request still surrenders its address, and the composer takes it.
  // That is the right recovery, but the payer scanned terms that are now gone,
  // so the reason travels with the address instead of being dropped in
  // silence. Which reason matters: only the multi-recipient case has a first
  // recipient the payer might not have meant.
  group('a refused request reports why only the address survived', () {
    test('more than one recipient', () {
      final result =
          resolveSendScanPayload(
                'zcash:?address=$_address&amount=0.25'
                '&address.1=$_address&amount.1=0.5',
                acceptedAddress: _address,
              )!
              as SendScanAddress;
      expect(result.downgrade, SendScanDowngrade.multipleRecipients);
    });

    test('a memo Vizor cannot read', () {
      // `_w` is base64url for 0xFF, which is not valid UTF-8.
      final result =
          resolveSendScanPayload(
                'zcash:$_address?amount=0.25&memo=_w',
                acceptedAddress: _address,
              )!
              as SendScanAddress;
      expect(result.downgrade, SendScanDowngrade.unsupportedMemo);
    });

    test('a request that does not parse', () {
      final result =
          resolveSendScanPayload(
                'zcash:$_address?amount=not-a-number',
                acceptedAddress: _address,
              )!
              as SendScanAddress;
      expect(result.downgrade, SendScanDowngrade.malformedRequest);
    });

    test('a custom asset lands in the catch-all, not the memo bucket', () {
      final result =
          resolveSendScanPayload(
                'zcash:$_address?req-asset=abcd',
                acceptedAddress: _address,
              )!
              as SendScanAddress;
      expect(result.downgrade, SendScanDowngrade.malformedRequest);
    });

    test('a payload that was never a payment request reports nothing', () {
      for (final raw in [
        _address,
        'not a uri at all',
        'bitcoin:bc1qexample?amount=1',
      ]) {
        final result =
            resolveSendScanPayload(raw, acceptedAddress: _address)!
                as SendScanAddress;
        expect(result.downgrade, isNull, reason: raw);
      }
    });
  });

  group('sendScanDowngradeMessage', () {
    test('names what was left behind, per reason', () {
      expect(
        sendScanDowngradeMessage(SendScanDowngrade.multipleRecipients),
        'Scanned the first recipient only — this request asks for more than '
        'one',
      );
      expect(
        sendScanDowngradeMessage(SendScanDowngrade.unsupportedMemo),
        "Scanned the address only — the request's message couldn't be read",
      );
      expect(
        sendScanDowngradeMessage(SendScanDowngrade.malformedRequest),
        "Scanned the address only — the payment request couldn't be read",
      );
    });

    test('a plain address QR says nothing', () {
      expect(sendScanDowngradeMessage(null), isNull);
    });

    test('every reason has a line', () {
      for (final downgrade in SendScanDowngrade.values) {
        expect(sendScanDowngradeMessage(downgrade), isNotNull);
      }
    });
  });
}
