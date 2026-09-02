import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';

void main() {
  group('friendlyProposeSendError', () {
    test("maps Rust's own no-tip wording onto the sync message", () {
      expect(
        friendlyProposeSendError(
          'Propose failed: Wallet must sync before sending max',
        ),
        'Finishing wallet sync. Try again shortly.',
      );
    });
  });

  group('friendlyPaymentRequestCheckError', () {
    test('names the network when the check could not reach it', () {
      expect(
        friendlyPaymentRequestCheckError('grpc connect failed: dns error'),
        "Couldn't reach the network — check your connection and open the "
        'link again',
      );
    });

    test('never claims a send happened for an unknown failure', () {
      final copy = friendlyPaymentRequestCheckError('something odd');
      expect(
        copy,
        "Couldn't check this request — open Edit to review the details",
      );
      expect(copy.toLowerCase(), isNot(contains('send failed')));
    });
  });

  group('sanitisePaymentRequestLabel', () {
    test('drops characters that can restyle the review screen', () {
      // U+202E is not whitespace, so the collapse alone left an unterminated
      // right-to-left override running through the "Requested by" row on the
      // surface whose whole job is stating what the user is consenting to.
      final label = sanitisePaymentRequestLabel('Alice\u202Egnidnep');

      expect(label, 'Alicegnidnep');
      expect(label, isNot(contains('\u202E')));
    });

    test('an invisible-only label is nothing to show', () {
      expect(sanitisePaymentRequestLabel('\u202E\u200F '), isNull);
    });

    test('still collapses whitespace and clamps the length', () {
      expect(sanitisePaymentRequestLabel('  Coffee\n shop  '), 'Coffee shop');
      final long = sanitisePaymentRequestLabel('a' * 100)!;
      expect(long.length, kPaymentRequestLabelMaxLength);
      expect(long.endsWith('…'), isTrue);
    });

    test('never splits a surrogate pair at the clamp boundary', () {
      // 100 astral-plane code points is 200 UTF-16 code units, so a
      // `substring` clamp lands mid-pair and leaves an unpaired surrogate
      // rendering as U+FFFD in the "Requested by" row.
      const emoji = '\u{1F600}';
      final clamped = sanitisePaymentRequestLabel(emoji * 100)!;

      expect(clamped.endsWith('…'), isTrue);
      expect(clamped.characters.length, kPaymentRequestLabelMaxLength);
      expect(clamped, '${emoji * (kPaymentRequestLabelMaxLength - 1)}…');
      expect(
        clamped.runes.any((rune) => rune >= 0xD800 && rune <= 0xDFFF),
        isFalse,
      );
    });

    test('counts a label the way the payer reads it', () {
      // Exactly at the limit in grapheme clusters, twice it in code units:
      // nothing to clamp, so nothing is cut and no ellipsis is invented.
      const emoji = '\u{1F600}';
      final atLimit = emoji * kPaymentRequestLabelMaxLength;

      expect(sanitisePaymentRequestLabel(atLimit), atLimit);
    });
  });
}
