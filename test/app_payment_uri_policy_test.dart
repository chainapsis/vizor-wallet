import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';

void main() {
  test('payment URI links are blocked while a send flow is active', () {
    for (final location in [
      '/send',
      '/send/amount',
      '/send/review',
      '/send/status',
      '/send/keystone-sign',
      '/send/keystone/scan',
    ]) {
      expect(paymentUriBlockedAtLocation(location), isTrue, reason: location);
    }
  });

  test('payment URI links are allowed outside send flows', () {
    for (final location in ['/home', '/unlock', '/activity', '/settings']) {
      expect(paymentUriBlockedAtLocation(location), isFalse, reason: location);
    }
  });
}
