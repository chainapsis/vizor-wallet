import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/domain/zip321_payment_request.dart';

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
}
