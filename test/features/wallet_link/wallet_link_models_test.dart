import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/wallet_link/models/wallet_link_models.dart';
import 'package:zcash_wallet/src/features/wallet_link/services/wallet_link_completion_crypto.dart';

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

void main() {
  test(
    'wallet link QR parses id and key without accepting endpoint authority',
    () {
      final key = _base64UrlNoPadding(List<int>.generate(32, (index) => index));
      final completionToken = _base64UrlNoPadding(
        List<int>.generate(32, (index) => 255 - index),
      );
      final payload = WalletLinkQrPayload.parse(
        'vizor://wallet-link/v1'
        '?id=550e8400-e29b-41d4-a716-446655440000'
        '&key=$key'
        '&completion=$completionToken'
        '&endpoint=https%3A%2F%2Fevil.example',
      );

      expect(payload.packageId, '550e8400-e29b-41d4-a716-446655440000');
      expect(payload.keyBytes, List<int>.generate(32, (index) => index));
      expect(payload.completionToken, completionToken);
    },
  );

  test(
    'wallet link completion summary round-trips with fixed ciphertext size',
    () async {
      final keyBytes = List<int>.generate(32, (index) => index);
      final first = await encryptWalletLinkImportSummary(
        summary: const WalletLinkImportSummary(
          importedAccountCount: 1,
          importedContactCount: 1,
        ),
        keyBytes: keyBytes,
      );
      final second = await encryptWalletLinkImportSummary(
        summary: const WalletLinkImportSummary(
          importedAccountCount: 22,
          importedContactCount: 333,
        ),
        keyBytes: keyBytes,
      );

      expect(first.ciphertext.length, 342);
      expect(second.ciphertext.length, first.ciphertext.length);

      final decoded = await decryptWalletLinkImportSummary(
        envelope: first,
        keyBytes: keyBytes,
      );
      expect(decoded.importedAccountCount, 1);
      expect(decoded.importedContactCount, 1);
    },
  );
}
