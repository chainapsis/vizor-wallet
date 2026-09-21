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

    test('refuses an encoded address key beside a different address key', () {
      // Two distinct decoded names, so the same-name guard does not fire —
      // but ZIP-321 forbids an encoded paramname outright, so `%61ddress`
      // cannot be the paramindex-0 payment and there is no single recipient.
      const raw = 'zcash:?address.1=u1real000&%61ddress=u1attacker0';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('refuses a query address appended to a positional address', () {
      // ZIP-321 makes the positional address the address of paramindex 0,
      // the same slot a bare `address=` names, so this is a repeat: the
      // victim reads the untampered prefix and the query value would win.
      const raw = 'zcash:u1real000?amount=0.5&address=u1attacker0';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('refuses a query address appended to a zcash:// authority', () {
      const raw = 'zcash://u1real000?address=u1attacker0';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('refuses an address key whose paramindex the parser rejects', () {
      // A paramindex the parser can never accept owns no slot, so beside a
      // well-formed key it is a second recipient with nothing to anchor it.
      // Classifying by validity used to let these skip the repeat check
      // entirely, and `_indexedZcashAddressFromUri` then recovered the one
      // remaining well-formed key — the appended attacker address.
      for (final malformed in [
        'address.0',
        'address.01',
        'address.10000',
        'address.1x',
        'addr%65ss.01',
      ]) {
        final raw = 'zcash:?$malformed=u1real000&address.1=u1attacker0';

        expect(normalizeAddressScanPayload(raw), raw, reason: malformed);
      }
    });

    test('refuses a lone address key with a rejected paramindex', () {
      // Nothing else in the payload names a recipient, so recovery has no
      // well-formed slot to fall back to either.
      const raw = 'zcash:u1real000?address.0=u1attacker0';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('keeps a positional address beside a higher indexed one', () {
      // paramindex 0 plus paramindex 1 is a legitimate multi-payment
      // request, not a repeat, so the positional address still recovers.
      expect(
        normalizeAddressScanPayload(
          'zcash:u1real000?address.1=u1second000&memo=not-base64url!',
        ),
        'u1real000',
      );
    });

    test('refuses a payload whose parameter name cannot be decoded', () {
      // `Uri.decodeQueryComponent('%FF')` throws `FormatException`, not
      // `ArgumentError`. A crafted QR must fail closed, never throw out of
      // the scan callback.
      const raw = 'zcash:?%FFx=y&address=u1real000&address=u1attacker0';

      expect(normalizeAddressScanPayload(raw), raw);
    });

    test('refuses a payload whose parameter value cannot be decoded', () {
      const raw = 'zcash:?address=u1real000&label=%FF';

      expect(normalizeAddressScanPayload(raw), raw);
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

    test('keeps a zcash:// authority address followed by a slash', () {
      // Dart parses `zcash://<addr>/` with `path == '/'`. A path of only
      // separators names no recipient, so the authority still has to win —
      // returning `/` filled the recipient field with a slash.
      expect(
        normalizeAddressScanPayload('zcash://t1KzCK7DjnDLmuFhNBmiZ/'),
        't1KzCK7DjnDLmuFhNBmiZ',
      );
      expect(
        normalizeAddressScanPayload('zcash://u1real000/?amount=1'),
        'u1real000',
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
