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

      expect(uri.scheme, 'vizor');
      expect(uri.host, 'payment-link');
      expect(uri.path, isEmpty);
      expect(uri.queryParameters['p'], isNotEmpty);
      expect(uri.fragment, isEmpty);
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

    test('compares the complete canonical payment-link payload', () {
      final original = _link();
      final roundTripped = VizorPaymentLink.parse(original.toUri().toString());

      expect(original.hasSameCanonicalPayload(roundTripped), isTrue);
      expect(
        original.hasSameCanonicalPayload(
          _link(
            network: ' main ',
            address: ' ${original.address} ',
            mnemonic: ' ${original.mnemonic} ',
            label: ' ${original.label} ',
            createdAt: DateTime.parse('2026-06-21T14:00:00+02:00'),
          ),
        ),
        isTrue,
      );

      final changedPayloads = <String, VizorPaymentLink>{
        'address': _link(address: '${original.address}2'),
        'amount': _link(amountZatoshi: original.amountZatoshi + BigInt.one),
        'mnemonic': _link(
          mnemonic:
              'legal winner thank year wave sausage worth useful legal winner thank yellow',
        ),
        'birthday': _link(birthdayHeight: original.birthdayHeight - 1),
        'label': _link(label: '${original.label} updated'),
        'createdAt': _link(
          createdAt: original.createdAt.add(const Duration(seconds: 1)),
        ),
        'presentation': _link(
          presentation: const PaymentLinkPresentation(message: 'Updated'),
        ),
      };
      for (final MapEntry(:key, :value) in changedPayloads.entries) {
        expect(original.hasSameCanonicalPayload(value), isFalse, reason: key);
      }
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
      final maxKoreanMessage = List.filled(128, '한').join();
      final maxSimpleEmojiMessage = List.filled(128, '🎉').join();
      expect(
        PaymentLinkPresentation(
          message: maxKoreanMessage,
        ).toPayload()?['message'],
        maxKoreanMessage,
      );
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
        () => VizorPaymentLink.parse('vizor://other?p=legacy'),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse('https://example.com/pay'),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse('vizor://payment-link/other?p=payload'),
        throwsFormatException,
      );
    });

    test('accepts the scheme and host case-insensitively', () {
      final link = _link();
      final uppercaseLink = link.toUri().toString().replaceFirst(
        'vizor://payment-link',
        'VIZOR://PAYMENT-LINK',
      );

      final decoded = VizorPaymentLink.parse(uppercaseLink);

      expect(decoded.address, link.address);
      expect(decoded.mnemonic, link.mnemonic);
    });

    test('rejects malformed payloads', () {
      expect(
        () => VizorPaymentLink.parse('vizor://payment-link?p=not-base64'),
        throwsFormatException,
      );
    });

    test('rejects oversized inbound links before decoding', () {
      expect(
        () => VizorPaymentLink.parse(
          'vizor://payment-link?p='
          '${'a' * VizorPaymentLink.maxEncodedLength}',
        ),
        throwsFormatException,
      );
    });

    test('rejects unsupported versions', () {
      final encoded = Uri(
        scheme: VizorPaymentLink.scheme,
        host: VizorPaymentLink.host,
        queryParameters: const {'p': 'eyJ2IjoyfQ=='},
      ).toString();

      expect(() => VizorPaymentLink.parse(encoded), throwsFormatException);
    });

    test('rejects extra URL components and duplicate payloads', () {
      final payload = _link().toUri().queryParameters['p']!;

      expect(
        () => VizorPaymentLink.parse(
          'vizor://payment-link?p=$payload&other=hidden',
        ),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse('vizor://user@payment-link?p=$payload'),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse('vizor://payment-link:8443?p=$payload'),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse(
          'vizor://payment-link?p=$payload&p=$payload',
        ),
        throwsFormatException,
      );
      expect(
        () => VizorPaymentLink.parse('vizor://payment-link?p=$payload#extra'),
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
        queryParameters: {
          'p': base64UrlEncode(utf8.encode(jsonEncode(payload))),
        },
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
  final encoded = uri.queryParameters['p']!;
  return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(encoded))))
      as Map<String, Object?>;
}

VizorPaymentLink _link({
  String network = 'main',
  String address = 'u1exampleaddress',
  BigInt? amountZatoshi,
  String mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
  int birthdayHeight = 3_456_789,
  String label = 'Demo link',
  DateTime? createdAt,
  PaymentLinkPresentation? presentation,
}) {
  return VizorPaymentLink(
    network: network,
    address: address,
    amountZatoshi: amountZatoshi ?? BigInt.from(123456789),
    mnemonic: mnemonic,
    birthdayHeight: birthdayHeight,
    label: label,
    createdAt: createdAt ?? DateTime.utc(2026, 6, 21, 12),
    presentation: presentation,
  );
}
