import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';

void main() {
  test('ZIP-321 memo text is sanitized at the send prefill boundary', () {
    final rawMemo = 'Pay \u202Eevil\u202C\u0001 now\u0007\nKeep emoji \u200D';
    final memo = base64Url.encode(utf8.encode(rawMemo)).replaceAll('=', '');
    final request = Zip321PaymentRequest.parse(
      'zcash:u1zip321destination?amount=1&memo=$memo',
    );

    final prefill = sendPrefillArgsFromZip321Payment(
      id: 'payment-uri-test',
      payment: request.primaryPayment,
    );

    expect(prefill.memoText, 'Pay evil now\nKeep emoji \u200D');
  });
}
