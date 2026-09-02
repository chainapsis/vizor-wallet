import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request_builder.dart';

const _shielded =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const _transparent = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';
const _message = 'Table 4 — two flat whites';

void main() {
  group('buildZip321PaymentUri', () {
    test('writes address and amount in ZIP-321 order', () {
      expect(
        buildZip321PaymentUri(address: _shielded, amountZec: '0.5'),
        'zcash:$_shielded?amount=0.5',
      );
    });

    test('never emits label or message', () {
      final uri = buildZip321PaymentUri(
        address: _shielded,
        amountZec: '0.5',
        memoText: _message,
      );

      // The account name is the only thing the wallet could put in these, and
      // it would travel to everyone the link reaches.
      expect(uri, isNot(contains('label=')));
      expect(uri, isNot(contains('message=')));
    });

    test('omits the memo parameter when there is no message', () {
      for (final memo in <String?>[null, '', '   ']) {
        expect(
          buildZip321PaymentUri(
            address: _shielded,
            amountZec: '0.5',
            memoText: memo,
          ),
          isNot(contains('memo=')),
        );
      }
    });

    test('encodes the memo as unpadded base64url', () {
      final uri = buildZip321PaymentUri(
        address: _shielded,
        amountZec: '0.5',
        memoText: _message,
      );
      final encoded = uri.split('&memo=').last;

      expect(encoded, isNot(contains('=')));
      expect(encoded, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
        _message,
      );
    });

    test('rejects a memo on a transparent address', () {
      expect(
        () => buildZip321PaymentUri(
          address: _transparent,
          amountZec: '0.5',
          memoText: _message,
        ),
        throwsA(
          isA<Zip321BuildException>().having(
            (e) => e.kind,
            'kind',
            Zip321BuildErrorKind.memoTransparent,
          ),
        ),
      );
    });

    test('rejects a memo over 512 bytes', () {
      // 171 three-byte characters is 513 bytes: over the limit while well
      // under 512 characters, which is exactly the case a character count
      // would wave through.
      final memo = '—' * 171;
      expect(utf8.encode(memo).length, greaterThan(kZip321MaxMemoBytes));
      expect(
        () => buildZip321PaymentUri(
          address: _shielded,
          amountZec: '0.5',
          memoText: memo,
        ),
        throwsA(
          isA<Zip321BuildException>().having(
            (e) => e.kind,
            'kind',
            Zip321BuildErrorKind.memoTooLong,
          ),
        ),
      );
    });

    test('accepts a memo of exactly 512 bytes', () {
      final memo = 'a' * kZip321MaxMemoBytes;
      expect(
        buildZip321PaymentUri(
          address: _shielded,
          amountZec: '0.5',
          memoText: memo,
        ),
        contains('&memo='),
      );
    });

    test('rejects an address that is not base-alphanumeric', () {
      expect(
        () => buildZip321PaymentUri(address: 'u1 bad', amountZec: '0.5'),
        throwsA(
          isA<Zip321BuildException>().having(
            (e) => e.kind,
            'kind',
            Zip321BuildErrorKind.address,
          ),
        ),
      );
    });
  });

  group('normalizeZip321Amount', () {
    test('strips trailing zeros without losing the value', () {
      expect(normalizeZip321Amount('0.50'), '0.5');
      expect(normalizeZip321Amount('0.5'), '0.5');
      expect(normalizeZip321Amount('1.00000000'), '1');
      expect(normalizeZip321Amount('1'), '1');
      expect(normalizeZip321Amount('0.000100'), '0.0001');
      expect(normalizeZip321Amount('00.5'), '0.5');
      expect(normalizeZip321Amount('0.00000001'), '0.00000001');
      expect(normalizeZip321Amount(' 0.50 '), '0.5');
    });

    test('keeps the whole ZEC supply', () {
      expect(normalizeZip321Amount('21000000'), '21000000');
    });

    test('rejects more than 8 decimals', () {
      expect(
        () => normalizeZip321Amount('0.123456789'),
        throwsA(
          isA<Zip321BuildException>().having(
            (e) => e.kind,
            'kind',
            Zip321BuildErrorKind.amountDecimals,
          ),
        ),
      );
    });

    test('rejects an amount above the ZEC supply', () {
      expect(
        () => normalizeZip321Amount('21000000.00000001'),
        throwsA(
          isA<Zip321BuildException>().having(
            (e) => e.kind,
            'kind',
            Zip321BuildErrorKind.amountSupply,
          ),
        ),
      );
    });

    test('rejects zero, blanks, exponents and signs', () {
      for (final value in ['', '   ', '0', '0.00', '5e2', '-1', '1,5', '.5']) {
        expect(
          () => normalizeZip321Amount(value),
          throwsA(isA<Zip321BuildException>()),
          reason: 'expected $value to be rejected',
        );
      }
    });
  });

  group('round trip through Zip321PaymentRequest.parse', () {
    test('shielded request with a message', () {
      final uri = buildZip321PaymentUri(
        address: _shielded,
        amountZec: '0.50',
        memoText: _message,
      );
      final payment = Zip321PaymentRequest.parse(uri).primaryPayment;

      expect(payment.address, _shielded);
      expect(payment.amount, '0.5');
      expect(payment.memoText, _message);
      expect(payment.memoIsBinary, isFalse);
      expect(payment.label, isNull);
      expect(payment.message, isNull);
    });

    test('shielded request without a message', () {
      final uri = buildZip321PaymentUri(address: _shielded, amountZec: '1.25');
      final payment = Zip321PaymentRequest.parse(uri).primaryPayment;

      expect(payment.address, _shielded);
      expect(payment.amount, '1.25');
      expect(payment.memoBase64Url, isNull);
    });

    test('transparent request carries no memo', () {
      final uri = buildZip321PaymentUri(
        address: _transparent,
        amountZec: '0.5',
        // A transparent request drops the message rather than failing: the
        // sheet never collects one, so a stale value must not block the link.
        memoText: null,
      );
      final request = Zip321PaymentRequest.parse(uri);

      expect(request.isSupported, isTrue);
      expect(request.primaryPayment.address, _transparent);
      expect(request.primaryPayment.amount, '0.5');
      expect(request.primaryPayment.memoBase64Url, isNull);
    });

    test('a 512-byte message survives the round trip', () {
      final memo = 'a' * kZip321MaxMemoBytes;
      final uri = buildZip321PaymentUri(
        address: _shielded,
        amountZec: '0.5',
        memoText: memo,
      );

      expect(Zip321PaymentRequest.parse(uri).primaryPayment.memoText, memo);
    });
  });

  test('zip321MemoByteLength counts bytes, not characters', () {
    expect(zip321MemoByteLength(_message), utf8.encode(_message).length);
    expect(zip321MemoByteLength('—'), 3);
  });
}
