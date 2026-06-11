import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/formatting/address_display.dart';

void main() {
  group('truncatedAddress', () {
    test('keeps head and tail of a long unified address', () {
      const address =
          'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
          '73d57f73c6dc05121591a83861cd190591';
      expect(truncatedAddress(address), 'u195091 ... 190591');
    });

    test('returns short addresses unchanged', () {
      expect(truncatedAddress('u1950'), 'u1950');
      expect(truncatedAddress(''), '');
    });

    test('returns addresses at the compact-length boundary unchanged', () {
      const boundary =
          kTruncatedAddressHeadLength +
          kTruncatedAddressTailLength +
          kTruncatedAddressSeparator.length;
      final atBoundary = 'a' * boundary;
      expect(truncatedAddress(atBoundary), atBoundary);

      final pastBoundary = 'abcdefghij${'k' * (boundary - 9)}';
      expect(pastBoundary.length, boundary + 1);
      expect(
        truncatedAddress(pastBoundary),
        'abcdefg ... ${pastBoundary.substring(pastBoundary.length - 6)}',
      );
    });

    test('trims surrounding whitespace before measuring', () {
      expect(truncatedAddress('  u1950  '), 'u1950');
    });
  });

  group('addressVerifyGrid', () {
    test('returns no rows for an empty address', () {
      expect(addressVerifyGrid(''), isEmpty);
      expect(addressVerifyGrid('   '), isEmpty);
    });

    test('chunks into 5-char groups, 5 groups per row', () {
      final address = List.generate(
        40,
        (i) => String.fromCharCode(97 + i % 26),
      ).join();
      expect(address.length, 40);

      final rows = addressVerifyGrid(address);
      expect(rows, hasLength(2));
      expect(rows[0], hasLength(kAddressVerifyGroupsPerRow));
      expect(rows[1], hasLength(3));
      for (final group in rows.expand((row) => row).take(7)) {
        expect(group.text, hasLength(kAddressVerifyGroupSize));
      }

      final reassembled = rows
          .expand((row) => row)
          .map((group) => group.text)
          .join();
      expect(reassembled, address);
    });

    test('leaves a shorter final group when length is not a multiple of 5', () {
      final rows = addressVerifyGrid('a' * 12);
      expect(rows, hasLength(1));
      expect(rows[0].map((g) => g.text).toList(), ['aaaaa', 'aaaaa', 'aa']);
    });

    test('fills exactly 8 rows for the 200-char design shape', () {
      final rows = addressVerifyGrid('a' * 200);
      expect(rows, hasLength(8));
      for (final row in rows) {
        expect(row, hasLength(kAddressVerifyGroupsPerRow));
      }
    });

    test('highlights the fixed non-consecutive mock positions', () {
      final rows = addressVerifyGrid('a' * 50);
      final groups = rows.expand((row) => row).toList();
      expect(groups, hasLength(10));
      // Figma mock pattern: groups 0 and 2, and the 3rd-last and last.
      expect(groups.map((g) => g.highlighted).toList(), [
        true,
        false,
        true,
        false,
        false,
        false,
        false,
        true,
        false,
        true,
      ]);
    });

    test('head/tail offsets overlap gracefully on a single row', () {
      final groups = addressVerifyGrid('a' * 25).expand((row) => row).toList();
      // 5 groups: head offsets {0,2} and tail offsets {4,2} -> 0,2,4.
      expect(groups.map((g) => g.highlighted).toList(), [
        true,
        false,
        true,
        false,
        true,
      ]);
    });

    test('overlapping head/tail ranges highlight every group once', () {
      final rows = addressVerifyGrid('abcdefgh');
      expect(rows, hasLength(1));
      expect(rows[0].map((g) => g.text).toList(), ['abcde', 'fgh']);
      expect(rows[0].every((g) => g.highlighted), isTrue);
    });

    test('boundary: exactly one full row of groups', () {
      final rows = addressVerifyGrid('a' * 25);
      expect(rows, hasLength(1));
      expect(rows[0], hasLength(5));
      // Head offsets {0,2} and tail offsets {N-1,N-3} coincide on group 2.
      expect(rows[0].map((g) => g.highlighted).toList(), [
        true,
        false,
        true,
        false,
        true,
      ]);
    });
  });
}
