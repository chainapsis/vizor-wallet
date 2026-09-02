import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/features/send/models/send_scan_result.dart';

const _address =
    'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
    '73d57f73c6dc05121591a83861cd190591';

void main() {
  group('resolveSendScanPayload', () {
    test('a bare address scans as a recipient', () {
      final result = resolveSendScanPayload(_address);
      expect(result, isA<SendScanAddress>());
      expect((result! as SendScanAddress).address, _address);
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
}
