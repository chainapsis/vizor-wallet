import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

void main() {
  test(
    'wallet link QR parses id and key without accepting endpoint authority',
    () {
      final key = _base64UrlNoPadding(List<int>.generate(32, (index) => index));
      final payload = WalletLinkQrPayload.parse(
        'vizor://wallet-link/v1'
        '?id=550e8400-e29b-41d4-a716-446655440000'
        '&key=$key'
        '&endpoint=https%3A%2F%2Fevil.example',
      );

      expect(payload.packageId, '550e8400-e29b-41d4-a716-446655440000');
      expect(payload.keyBytes, List<int>.generate(32, (index) => index));
    },
  );
}
