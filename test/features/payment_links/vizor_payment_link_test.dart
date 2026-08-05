import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';

void main() {
  group('VizorPaymentLink', () {
    test('round trips a payment link payload', () {
      final link = VizorPaymentLink(
        network: 'main',
        address: 'u1exampleaddress',
        amountZatoshi: BigInt.from(123456789),
        mnemonic:
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        birthdayHeight: 3_456_789,
        label: 'Demo link',
        createdAt: DateTime.utc(2026, 6, 21, 12),
      );

      final encoded = link.encode();
      final decoded = VizorPaymentLink.decode(encoded);

      expect(encoded, startsWith('vizor://payment-link?p='));
      expect(decoded.network, 'main');
      expect(decoded.address, link.address);
      expect(decoded.amountZatoshi, BigInt.from(123456789));
      expect(decoded.mnemonic, link.mnemonic);
      expect(decoded.birthdayHeight, 3_456_789);
      expect(decoded.label, link.label);
      expect(decoded.createdAt, link.createdAt);
    });

    test('rejects links without Vizor payment-link scheme', () {
      expect(
        () => VizorPaymentLink.decode('https://example.com/pay'),
        throwsFormatException,
      );
    });

    test('rejects malformed payloads', () {
      expect(
        () => VizorPaymentLink.decode('vizor://payment-link?p=not-base64'),
        throwsFormatException,
      );
    });

    test('rejects oversized inbound links before decoding', () {
      expect(
        () => VizorPaymentLink.decode(
          'vizor://payment-link?p=${'a' * VizorPaymentLink.maxEncodedLength}',
        ),
        throwsFormatException,
      );
    });

    test('rejects unsupported versions', () {
      final encoded = Uri(
        scheme: 'vizor',
        host: 'payment-link',
        queryParameters: {'p': 'eyJ2IjoyfQ=='},
      ).toString();

      expect(() => VizorPaymentLink.decode(encoded), throwsFormatException);
    });

    test('rejects links without network', () {
      final payload = {
        'v': 1,
        'address': 'u1exampleaddress',
        'amountZatoshi': '1',
        'mnemonic':
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        'birthdayHeight': 1,
        'label': 'Demo link',
        'createdAt': DateTime.utc(2026, 6, 21).toIso8601String(),
      };
      final encoded = Uri(
        scheme: VizorPaymentLink.scheme,
        host: VizorPaymentLink.host,
        queryParameters: {
          'p': base64UrlEncode(utf8.encode(jsonEncode(payload))),
        },
      ).toString();

      expect(() => VizorPaymentLink.decode(encoded), throwsFormatException);
    });
  });
}
