// Lane-agnostic: invoke this untagged file directly with
// --dart-define=VIZOR_FORM_FACTOR=mobile to exercise mobile tokens.
// --tags mobile excludes untagged files.

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';

import 'support/request_amount_test_support.dart';

void main() {
  group('ZecRequestView', () {
    test('an empty amount encodes the plain address, not a request', () {
      expect(emptyRequest.qrData, testShieldedAddress);
      expect(emptyRequest.requestUri, isNull);
      expect(emptyRequest.isReady, isFalse);
      expect(emptyRequest.summaryAmountText, isNull);
    });

    test('an amount turns the address QR into a request QR', () {
      expect(
        requestWithAmount.qrData,
        startsWith('zcash:$testShieldedAddress?amount=0.5'),
      );
      expect(requestWithAmount.isReady, isTrue);
      expect(requestWithAmount.summaryAmountText, '0.5 ZEC');
    });

    test('a transparent request drops the message entirely', () {
      const withStaleMessage = ZecRequestView(
        address: testTransparentAddress,
        amountZec: '0.5',
        messageText: testMessage,
      );

      expect(withStaleMessage.effectiveMessage, isNull);
      expect(withStaleMessage.requestUri, isNot(contains('memo=')));
    });

    test('an unusable amount is not a request yet, and is not an error', () {
      expect(requestWithError.requestUri, isNull);
      expect(requestWithError.qrData, testShieldedAddress);
    });
  });
}
