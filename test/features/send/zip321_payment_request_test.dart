import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';

void main() {
  test('parses a CipherPay-style ZIP-321 payment URI', () {
    final memo = base64Url
        .encode(utf8.encode('CP-C6CDB775'))
        .replaceAll('=', '');

    final request = Zip321PaymentRequest.parse(
      'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez'
      '?amount=0.12345678&memo=$memo&label=Acme%20Store',
    );

    expect(request.isSupported, isTrue);
    expect(request.payments, hasLength(1));
    expect(
      request.primaryPayment.address,
      'ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez',
    );
    expect(request.primaryPayment.amount, '0.12345678');
    expect(request.primaryPayment.memoText, 'CP-C6CDB775');
    expect(request.primaryPayment.label, 'Acme Store');
  });

  test('rejects unsupported required parameters', () {
    expect(
      () => Zip321PaymentRequest.parse(
        'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?req-unknown=1',
      ),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'Required ZIP-321 parameter req-unknown is not supported.',
        ),
      ),
    );
  });

  test('rejects payment URIs longer than the shared native bound', () {
    final oversized =
        'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?message='
        '${'a' * kMaxPaymentUriLength}';

    expect(oversized.length, greaterThan(kMaxPaymentUriLength));
    expect(
      () => Zip321PaymentRequest.parse(oversized),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'Payment link is too long.',
        ),
      ),
    );
  });

  test('truncates an over-long echoed parameter name', () {
    final longName = 'req-${'a' * 60}';

    expect(
      () => Zip321PaymentRequest.parse(
        'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?$longName=1',
      ),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'Required ZIP-321 parameter req-${'a' * 28}… is not supported.',
        ),
      ),
    );
  });

  test('marks multiple-recipient requests as parsed but unsupported', () {
    final request = Zip321PaymentRequest.parse(
      'zcash:?address=u1firstaddress&amount=1'
      '&address.1=u1secondaddress&amount.1=2',
    );

    expect(request.payments, hasLength(2));
    expect(request.isSupported, isFalse);
    expect(
      request.unsupportedReason,
      'Multiple-recipient ZIP-321 requests are parsed but not supported yet.',
    );
  });

  test('rejects memo on transparent addresses', () {
    final memo = base64Url.encode(utf8.encode('hello')).replaceAll('=', '');

    expect(
      () => Zip321PaymentRequest.parse('zcash:t1transparent?memo=$memo'),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'Transparent ZIP-321 payments cannot include a memo.',
        ),
      ),
    );
  });

  test('rejects oversized memo before base64 decoding', () {
    final oversizedMemo = 'A' * 685;

    expect(
      () => Zip321PaymentRequest.parse(
        'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?memo=$oversizedMemo',
      ),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'ZIP-321 memo exceeds 512 bytes.',
        ),
      ),
    );
  });

  test('accepts a zero-padded full-width ZIP-302 memo field', () {
    // ZIP-302 memos are a fixed 512-byte field; producers that transmit the
    // whole field right-pad the text with NULs.
    final bytes = List<int>.filled(512, 0);
    bytes.setRange(0, 10, utf8.encode('Invoice 42'));
    final memo = base64Url.encode(bytes).replaceAll('=', '');

    final request = Zip321PaymentRequest.parse(
      'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?memo=$memo',
    );

    expect(request.isSupported, isTrue);
    expect(request.primaryPayment.memoText, 'Invoice 42');
    expect(request.primaryPayment.memoIsBinary, isFalse);
  });

  test('still rejects a memo with an interior NUL byte', () {
    final bytes = <int>[
      ...utf8.encode('Inv'),
      0x00,
      ...utf8.encode('42'),
      0x00,
    ];
    final memo = base64Url.encode(bytes).replaceAll('=', '');

    expect(
      () => Zip321PaymentRequest.parse(
        'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?memo=$memo',
      ),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'ZIP-321 memo contains unsupported control characters.',
        ),
      ),
    );
  });

  test('rejects text memo with unsupported control characters', () {
    final rawMemo = 'Pay \u202Eevil\u202C\u0001 now';
    final memo = base64Url.encode(utf8.encode(rawMemo)).replaceAll('=', '');

    expect(
      () => Zip321PaymentRequest.parse(
        'zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez?memo=$memo',
      ),
      throwsA(
        isA<Zip321ParseException>().having(
          (e) => e.message,
          'message',
          'ZIP-321 memo contains unsupported control characters.',
        ),
      ),
    );
  });
}
