import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/zip321_payment_request.dart';

void main() {
  group('Zip321PaymentRequest', () {
    test('parses a single-address payment URI', () {
      final request = Zip321PaymentRequest.parse(
        'zcash:u1zip321destination?amount=1.25&message=Invoice%2042',
      );

      expect(request.isSupported, isTrue);
      expect(request.payments, hasLength(1));
      expect(request.primaryPayment.address, 'u1zip321destination');
      expect(request.primaryPayment.amount, '1.25');
      expect(request.primaryPayment.message, 'Invoice 42');
    });

    test('parses query-address form as an equivalent payment', () {
      final request = Zip321PaymentRequest.parse(
        'zcash:?address=u1zip321destination&amount=0.00000001',
      );

      expect(request.isSupported, isTrue);
      expect(request.primaryPayment.address, 'u1zip321destination');
      expect(request.primaryPayment.amount, '0.00000001');
    });

    test('ignores unknown non-required parameters', () {
      final request = Zip321PaymentRequest.parse(
        'zcash:u1zip321destination?amount=1&memo-format=ignored',
      );

      expect(request.isSupported, isTrue);
      expect(request.payments, hasLength(1));
      expect(request.primaryPayment.amount, '1');
    });

    test('decodes base64url memo text for shielded payment handoff', () {
      final request = Zip321PaymentRequest.parse(
        'zcash:u1zip321destination?amount=1&memo=VGhpcyBpcyBhIHNpbXBsZSBtZW1vLg',
      );

      expect(request.isSupported, isTrue);
      expect(request.primaryPayment.memoText, 'This is a simple memo.');
      expect(request.primaryPayment.memoIsBinary, isFalse);
    });

    test('parses binary memos as unsupported by the prototype', () {
      final request = Zip321PaymentRequest.parse(
        'zcash:u1zip321destination?amount=1&memo=_w',
      );

      expect(request.isSupported, isFalse);
      expect(
        request.unsupportedReason,
        'Binary ZIP-321 memos are parsed but not supported yet.',
      );
    });

    test(
      'parses valid multi-payment requests as unsupported by the prototype',
      () {
        final request = Zip321PaymentRequest.parse(
          'zcash:?address=u1first&amount=1&address.1=u1second&amount.1=2',
        );

        expect(request.isSupported, isFalse);
        expect(request.payments, hasLength(2));
        expect(
          request.unsupportedReason,
          'Multiple-recipient ZIP-321 requests are parsed but not supported yet.',
        );
      },
    );

    test('parses custom asset requests as unsupported by the prototype', () {
      final request = Zip321PaymentRequest.parse(
        'zcash:?address=u1assetrequest&req-asset=AEcnAAAAAAAAAA',
      );

      expect(request.isSupported, isFalse);
      expect(
        request.unsupportedReason,
        'Custom asset ZIP-321 requests are parsed but not supported yet.',
      );
    });

    test('rejects invalid amount syntax', () {
      expect(
        () => Zip321PaymentRequest.parse(
          'zcash:u1zip321destination?amount=0.123456789',
        ),
        throwsA(isA<Zip321ParseException>()),
      );
    });

    test('rejects duplicate indexed parameters', () {
      expect(
        () => Zip321PaymentRequest.parse(
          'zcash:?address=u1zip321destination&amount=1&amount=2',
        ),
        throwsA(isA<Zip321ParseException>()),
      );
    });

    test('rejects non-address parameters without an address', () {
      expect(
        () => Zip321PaymentRequest.parse('zcash:?amount=1'),
        throwsA(isA<Zip321ParseException>()),
      );
    });

    test('rejects hierarchical URI shape', () {
      expect(
        () =>
            Zip321PaymentRequest.parse('zcash://u1zip321destination?amount=1'),
        throwsA(isA<Zip321ParseException>()),
      );
    });

    test('rejects unknown required parameters', () {
      expect(
        () => Zip321PaymentRequest.parse(
          'zcash:u1zip321destination?req-extra=value',
        ),
        throwsA(isA<Zip321ParseException>()),
      );
    });
  });
}
