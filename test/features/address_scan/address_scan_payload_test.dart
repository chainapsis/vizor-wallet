import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/address_scan/domain/address_scan_payload.dart';

void main() {
  group('normalizeAddressScanPayload', () {
    test('keeps raw addresses', () {
      expect(normalizeAddressScanPayload('  rowan.near  '), 'rowan.near');
    });

    test('extracts recipient from ethereum receive URI', () {
      expect(
        normalizeAddressScanPayload(
          'ethereum:0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
        ),
        '0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
      );
    });

    test('drops ethereum chain id suffix', () {
      expect(
        normalizeAddressScanPayload(
          'ethereum:0x157D19957d4047Fb8601783805a54EF6ae80eaD7@8453',
        ),
        '0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
      );
    });

    test('extracts ERC-681 transfer recipient instead of token contract', () {
      expect(
        normalizeAddressScanPayload(
          'ethereum:0x1111111111111111111111111111111111111111@1'
          '/transfer?address=0x157D19957d4047Fb8601783805a54EF6ae80eaD7'
          '&uint256=1000000',
        ),
        '0x157D19957d4047Fb8601783805a54EF6ae80eaD7',
      );
    });

    test('extracts address from zcash ZIP-321 URI', () {
      expect(
        normalizeAddressScanPayload(
          'zcash:u1k8h8x9g7f6e5d4c3b2a1?amount=0.01&message=hello',
        ),
        'u1k8h8x9g7f6e5d4c3b2a1',
      );
    });

    test('extracts bare query address from zcash ZIP-321 URI', () {
      expect(
        normalizeAddressScanPayload('zcash:?address=u1k8h8x9g7f6e5d4c3b2a1'),
        'u1k8h8x9g7f6e5d4c3b2a1',
      );
    });

    test('refuses a percent-encoded alias of a repeated address key', () {
      // The parser refuses the encoded name, and the recovery path must not
      // let `Uri.queryParameters` decode it into a second `address` that
      // wins by being last.
      // Refusal hands the raw payload back unchanged, exactly like the
      // plainly repeated key below, so nothing downstream sees an address.
      const encodedAlias = 'zcash:?address=u1real000&%61ddress=u1attacker0';
      expect(normalizeAddressScanPayload(encodedAlias), encodedAlias);
      const encodedIndex = 'zcash:?address.1=u1real000&address.%31=u1attacker0';
      expect(normalizeAddressScanPayload(encodedIndex), encodedIndex);
    });

    test('a single encoded address key is not a repeat', () {
      expect(
        normalizeAddressScanPayload('zcash:?%61ddress=u1real000'),
        'u1real000',
      );
    });

    test('extracts an indexed-only zcash address', () {
      expect(
        normalizeAddressScanPayload('zcash:?address.1=u1k8h8x9g7f6e5d4c3b2a1'),
        'u1k8h8x9g7f6e5d4c3b2a1',
      );
    });

    test('prefers the lowest indexed zcash address', () {
      expect(
        normalizeAddressScanPayload(
          'zcash:?address.5=u1fifthaddress&address.2=u1secondaddress',
        ),
        'u1secondaddress',
      );
    });

    test('recovers an indexed zcash address when the memo is rejected', () {
      final memo = base64Url
          .encode(utf8.encode('Pay \u202Eevil\u202C now'))
          .replaceAll('=', '');

      expect(
        normalizeAddressScanPayload(
          'zcash:?address.1=u1k8h8x9g7f6e5d4c3b2a1&memo.1=$memo',
        ),
        'u1k8h8x9g7f6e5d4c3b2a1',
      );
    });

    test('refuses to recover an address the parser found ambiguous', () {
      // `Uri.queryParameters` keeps the last value, so recovering here would
      // hand the scan the attacker's address instead of the payee's.
      const raw = 'zcash:?address.1=u1realrecipient&address.1=u1attacker';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('refuses a repeated bare address key too', () {
      const raw =
          'zcash:?address=u1realrecipient&address=u1attacker'
          '&memo=not-base64url!';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('keeps the case of a zcash:// authority address', () {
      // `uri.host` is lowercased, which corrupts a transparent or TEX address.
      expect(
        normalizeAddressScanPayload('zcash://t1KzCK7DjnDLmuFhNBmiZ?amount=1'),
        't1KzCK7DjnDLmuFhNBmiZ',
      );
    });

    test('leaves unsupported schemes unchanged', () {
      expect(
        normalizeAddressScanPayload('wc:abc@2?relay-protocol=irn'),
        'wc:abc@2?relay-protocol=irn',
      );
    });
  });
}
