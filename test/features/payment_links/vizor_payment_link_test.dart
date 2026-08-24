import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';

void main() {
  group('VizorPaymentLink', () {
    test('round trips a payment link payload', () {
      final link = _link(
        presentation: const PaymentLinkPresentation(
          artworkId: 'celebration_03',
          message: '축하해! 🎉',
        ),
      );

      final uri = link.toUri();
      final decoded = VizorPaymentLink.parse(uri.toString());
      final payload = _decodePayload(uri);

      expect(uri.scheme, 'https');
      expect(uri.host, 'functions.vizor.cash');
      expect(uri.path, '/payment-links/open');
      expect(uri.query, isEmpty);
      expect(uri.fragment, startsWith('v1='));
      expect(decoded.network, 'main');
      expect(decoded.address, link.address);
      expect(decoded.amountZatoshi, BigInt.from(123456789));
      expect(decoded.mnemonic, link.mnemonic);
      expect(decoded.birthdayHeight, 3_456_789);
      expect(decoded.label, link.label);
      expect(decoded.createdAt, link.createdAt);
      expect(decoded.presentation?.artworkId, 'celebration_03');
      expect(decoded.presentation?.message, '축하해! 🎉');
      expect(payload['presentation'], {
        'artworkId': 'celebration_03',
        'message': '축하해! 🎉',
      });
    });

    test('omits an empty presentation payload', () {
      final uri = _link(
        presentation: const PaymentLinkPresentation(
          artworkId: '  ',
          message: '  ',
        ),
      ).toUri();
      final payload = _decodePayload(uri);

      expect(payload, isNot(contains('presentation')));
      expect(VizorPaymentLink.parse(uri.toString()).presentation, isNull);
    });

    test('rejects invalid presentation values', () {
      final maxSimpleEmojiMessage = List.filled(128, '🎉').join();
      expect(
        PaymentLinkPresentation(
          message: maxSimpleEmojiMessage,
        ).toPayload()?['message'],
        maxSimpleEmojiMessage,
      );
      expect(
        () => _link(
          presentation: const PaymentLinkPresentation(
            artworkId: 'not an artwork id',
          ),
        ).toUri(),
        throwsFormatException,
      );
      expect(
        () => _link(
          presentation: PaymentLinkPresentation(
            message: List.filled(129, 'a').join(),
          ),
        ).toUri(),
        throwsFormatException,
      );
      expect(
        () => _link(
          presentation: PaymentLinkPresentation(
            message: List.filled(25, '👨‍👩‍👧‍👦').join(),
          ),
        ).toUri(),
        throwsFormatException,
      );
    });

    test('rejects URLs outside the Vizor payment-link endpoint', () {
      expect(
        () => VizorPaymentLink.parse('vizor://payment-link?p=legacy'),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse('https://example.com/pay'),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse(
          'https://functions.vizor.cash/payment-links/other#v1=payload',
        ),
        throwsFormatException,
      );
    });

    test('accepts the scheme and host case-insensitively', () {
      final link = _link();
      final uppercaseLink = link.toUri().toString().replaceFirst(
        'https://functions.vizor.cash',
        'HTTPS://FUNCTIONS.VIZOR.CASH',
      );

      final decoded = VizorPaymentLink.parse(uppercaseLink);

      expect(decoded.address, link.address);
      expect(decoded.mnemonic, link.mnemonic);
    });

    test('rejects malformed payloads', () {
      expect(
        () => VizorPaymentLink.parse(
          'https://functions.vizor.cash/payment-links/open#v1=not-base64',
        ),
        throwsFormatException,
      );
    });

    test('rejects oversized inbound links before decoding', () {
      expect(
        () => VizorPaymentLink.parse(
          'https://functions.vizor.cash/payment-links/open#v1='
          '${'a' * VizorPaymentLink.maxEncodedLength}',
        ),
        throwsFormatException,
      );
    });

    test('rejects unsupported versions', () {
      final encoded = Uri(
        scheme: VizorPaymentLink.scheme,
        host: VizorPaymentLink.host,
        path: VizorPaymentLink.path,
        fragment: 'v1=eyJ2IjoyfQ==',
      ).toString();

      expect(() => VizorPaymentLink.parse(encoded), throwsFormatException);
    });

    test('rejects query parameters, credentials, and explicit ports', () {
      final payload = _link().toUri().fragment;

      expect(
        () => VizorPaymentLink.parse(
          'https://functions.vizor.cash/payment-links/open?payload=hidden#$payload',
        ),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse(
          'https://user@functions.vizor.cash/payment-links/open#$payload',
        ),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse(
          'https://functions.vizor.cash:8443/payment-links/open#$payload',
        ),
        throwsFormatException,
      );
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
        path: VizorPaymentLink.path,
        fragment: 'v1=${base64UrlEncode(utf8.encode(jsonEncode(payload)))}',
      ).toString();

      expect(() => VizorPaymentLink.parse(encoded), throwsFormatException);
    });

    test('rejects non-mainnet payment links', () {
      final testnetLink = VizorPaymentLink(
        network: 'test',
        address: 'utest1exampleaddress',
        amountZatoshi: BigInt.one,
        mnemonic:
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        birthdayHeight: 1,
        label: 'Test link',
        createdAt: DateTime.utc(2026, 8, 24),
      );

      expect(testnetLink.toUri, throwsFormatException);
    });
  });
}

Map<String, Object?> _decodePayload(Uri uri) {
  final encoded = uri.fragment.substring('v1='.length);
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded))))
      as Map<String, Object?>;
}

VizorPaymentLink _link({PaymentLinkPresentation? presentation}) {
  return VizorPaymentLink(
    network: 'main',
    address: 'u1exampleaddress',
    amountZatoshi: BigInt.from(123456789),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 3_456_789,
    label: 'Demo link',
    createdAt: DateTime.utc(2026, 6, 21, 12),
    presentation: presentation,
  );
}
