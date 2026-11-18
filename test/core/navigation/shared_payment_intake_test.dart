import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/shared_payment_intake.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';
import 'package:zcash_wallet/src/services/shared_payment_service.dart';

// Shared text is the one intake where a payment arrives surrounded by other
// text, so what is pulled out of it, and in what order, is the whole feature.
// The QR reader is a fake: this is about which strings reach the lanes.
void main() {
  const transparent = 'tmEjY6KfCryQhJ1hKSGiA7p8EeVggpvN78r';
  const unified =
      'u1qpzry9x8gf2tvdw0s3jn54khce6mua7lqpzry9x8gf2tvdw0s3jn54khce6mua7l';
  const regtest =
      'uregtest1qpzry9x8gf2tvdw0s3jn54khce6mua7lqpzry9x8gf2tvdw0s3jn54khce6';
  const link = 'zcash:$transparent?amount=1';
  final giftLink = 'https://${VizorDeepLink.host}/payment-links/open#v1=abcdef';
  Future<List<String>> noCodes(String path) async => [];

  group('sharedPaymentAddress', () {
    test('an address is found bare or inside prose, quotes, brackets or '
        'Markdown emphasis', () {
      expect(sharedPaymentAddress(transparent), transparent);
      expect(
        sharedPaymentAddress('Please pay me at $transparent thanks'),
        transparent,
      );
      expect(sharedPaymentAddress('Use "$unified" or ($transparent)'), unified);
      expect(
        sharedPaymentAddress('Pay _${transparent}_ or *$unified*'),
        transparent,
      );
    });

    test('every network is found, in either letter case', () {
      expect(sharedPaymentAddress('on regtest: $regtest'), regtest);
      expect(
        sharedPaymentAddress('ZS1${'QPZRY9X8GF2TVDW0S3JN54KHCE6MUA7L' * 2}'),
        startsWith('ZS1'),
      );
    });

    test('an address inside an explorer link is found', () {
      expect(
        sharedPaymentAddress('https://explorer.example/address/$unified'),
        unified,
      );
    });

    test('prose, hashes, ids and words only shaped like an address are not '
        'addresses', () {
      expect(sharedPaymentAddress('Hello world, just checking in'), isNull);
      expect(
        sharedPaymentAddress('8f3c2a9b7d1e4f6a0b5c8d2e7f1a3b9c' * 2),
        isNull,
      );
      // The bech32 alphabet has no b, i, o or 1.
      expect(
        sharedPaymentAddress(
          'u1qwertyuiopasdfghjklzxcvbnm0123456789qwertyuiopasdfghjklzxcvbnm',
        ),
        isNull,
      );
      // A transparent address is exactly 35 characters.
      expect(sharedPaymentAddress('${transparent}x'), isNull);
      expect(sharedPaymentAddress(transparent.substring(0, 34)), isNull);
    });
  });

  group('sharedPaymentLinks', () {
    test('a link keeps its query and loses the punctuation that ends a '
        'sentence', () {
      expect(sharedPaymentLinks('Send it to $link.'), [link]);
      expect(sharedPaymentLinks('Gift: $giftLink!'), [giftLink]);
      expect(sharedPaymentLinks(transparent), isEmpty);
    });

    test('a link keeps apostrophes and brackets that belong to it and loses '
        'only the ones wrapped around it', () {
      const labelled = "zcash:$transparent?label=Bob's&amount=1";
      expect(sharedPaymentLinks(labelled), [labelled]);
      expect(sharedPaymentLinks('"$labelled"'), [labelled]);
      // The quote before the link closes it once, however many it holds.
      expect(sharedPaymentLinks("'$labelled'"), [labelled]);
      expect(sharedPaymentLinks("Pay ('$labelled')."), [labelled]);
      expect(sharedPaymentLinks('Pay ($labelled).'), [labelled]);
      expect(sharedPaymentLinks('<$labelled>'), [labelled]);
      const bracketedLabel = 'zcash:$transparent?label=(a)';
      expect(sharedPaymentLinks('($bracketedLabel)'), [bracketedLabel]);
      expect(sharedPaymentLinks("'$link'"), [link]);
    });

    test('a link ends where the ASCII does: typographic quotes, CJK brackets, '
        'stops and prose with no space before them', () {
      const labelled = "zcash:$transparent?label=Bob's&amount=1";
      expect(sharedPaymentLinks('Pay “$labelled”'), [labelled]);
      expect(sharedPaymentLinks('‘$labelled’'), [labelled]);
      expect(sharedPaymentLinks('«$link»'), [link]);
      expect(sharedPaymentLinks('「$link」'), [link]);
      expect(sharedPaymentLinks('（$link）'), [link]);
      expect(sharedPaymentLinks('请付款 $link。'), [link]);
      expect(sharedPaymentLinks('请付款：$link。谢谢'), [link]);
      expect(sharedPaymentLinks('送って $link！'), [link]);
      expect(sharedPaymentLinks('$link…'), [link]);
    });

    test('a link with a raw non-ASCII label is not cut into a smaller request; '
        'prose run up against a link still is', () {
      // Not a valid request (the label is not percent-encoded), so the lane
      // rejects it whole rather than being offered `?label=` alone.
      const raw = 'zcash:$transparent?label=咖啡&amount=1&memo=aGk';
      expect(() => Zip321PaymentRequest.parse(raw), throwsA(anything));
      expect(sharedPaymentLinks(raw), [raw]);
      expect(sharedPaymentLinks('请付款 $raw。'), [raw]);
      expect(sharedPaymentLinks('Pay “$raw”'), [raw]);
      expect(
        resolveSharedText(raw),
        isA<SharedPaymentRequest>().having((r) => r.raw, 'raw', raw),
      );
      expect(sharedPaymentLinks('$link付款'), [link]);
      expect(sharedPaymentLinks('请付款：$link谢谢'), [link]);
      // A request run up against the next link stays its own.
      const next = 'zcash:$unified?amount=2&memo=aGk';
      expect(sharedPaymentLinks('$link和$next'), [link, next]);
      expect(sharedPaymentLinks('付款$link或https://example.com/pay?a=1&b=2'), [
        link,
        'https://example.com/pay?a=1&b=2',
      ]);
      // Carrying links on must stay linear: the shared text can be 64 KB.
      final watch = Stopwatch()..start();
      sharedPaymentLinks('zcash:a字' * 8000);
      sharedPaymentLinks('zcash:aa&b=字' * 5000);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a wrapped link is kept whole inside its wrapper, ASCII, typographic '
        'or Markdown', () {
      const paid = 'zcash:$transparent?amount=1&message=Paid!';
      expect(sharedPaymentLinks('Pay “$paid”'), [paid]);
      expect(sharedPaymentLinks('Pay "$paid" now'), [paid]);
      expect(sharedPaymentLinks("'$paid'"), [paid]);
      expect(sharedPaymentLinks('($paid)'), [paid]);
      expect(sharedPaymentLinks('**$link**'), [link]);
      expect(sharedPaymentLinks('_${link}_'), [link]);
      expect(sharedPaymentLinks('[pay]($link)'), [link]);
      // Outside the wrapper, prose is still prose.
      expect(sharedPaymentLinks('("$paid").'), [paid]);
    });

    test("a trailing underscore or asterisk is the link's own unless it twins "
        'an opener before the link', () {
      // base64url: `aGk_` is the memo "hi?"; without the underscore it reads
      // "hi", and the card would show a memo the sender never wrote.
      const memo = 'zcash:$transparent?amount=1&memo=aGk_';
      expect(sharedPaymentLinks('see $memo'), [memo]);
      expect(sharedPaymentLinks('see $memo.'), [memo]);
      const starred = 'zcash:$transparent?amount=1&label=a*';
      expect(sharedPaymentLinks('see $starred'), [starred]);
      expect(sharedPaymentLinks('_${memo}_'), [memo]);
      expect(sharedPaymentLinks('*$starred*'), [starred]);
    });

    test('text that is nothing but a link is handed on untouched', () {
      // `!` and `)` are legal in a ZIP-321 value, and with no prose around
      // the link nothing else could have put them there.
      const paid = 'zcash:$transparent?amount=1&message=Paid!';
      expect(sharedPaymentLinks(paid), [paid]);
      expect(sharedPaymentLinks('  $paid\n'), [paid]);
      const bracketed = 'zcash:$transparent?label=(a)';
      expect(sharedPaymentLinks(bracketed), [bracketed]);
      expect(
        resolveSharedText(paid),
        isA<SharedPaymentRequest>().having((r) => r.raw, 'raw', paid),
      );
      // Inside a sentence the same link still loses sentence punctuation.
      expect(sharedPaymentLinks('Done: $paid'), [
        paid.substring(0, paid.length - 1),
      ]);
    });

    test(
      'a link followed by thousands of brackets is trimmed in its stride',
      () {
        // Recounting the brackets per trimmed character would make this
        // quadratic, and the shared text can be 64 KB.
        expect(sharedPaymentLinks('see $link${')' * 60000}'), [link]);
      },
    );
  });

  group('resolveSharedText', () {
    test('a bare address becomes a request for zcash:<address>', () {
      expect(
        resolveSharedText('pay $transparent'),
        isA<SharedPaymentRequest>().having(
          (r) => r.raw,
          'raw',
          'zcash:$transparent',
        ),
      );
    });

    test(
      'the first address wins; whether it is real is the card\'s to say',
      () {
        expect(
          resolveSharedText('$transparent then $unified'),
          isA<SharedPaymentRequest>().having(
            (r) => r.raw,
            'raw',
            'zcash:$transparent',
          ),
        );
      },
    );

    test('a zcash: link is handed on as written before any address, whatever '
        'the text order', () {
      expect(
        resolveSharedText('$transparent or $link'),
        isA<SharedPaymentRequest>().having((r) => r.raw, 'raw', link),
      );
      // Parsing is the lane's job: a broken link gets its rejection sentence
      // there, not silence here.
      expect(
        resolveSharedText('zcash:not-an-address?amount=x'),
        isA<SharedPaymentRequest>().having(
          (r) => r.raw,
          'raw',
          'zcash:not-an-address?amount=x',
        ),
      );
    });

    test('a Gift Card link on the Vizor origin is handed on; other https '
        'links and the bare origin are not', () {
      expect(
        resolveSharedText('Here is your gift: $giftLink'),
        isA<SharedGiftCard>().having((g) => g.link, 'link', giftLink),
      );
      expect(
        resolveSharedText('https://example.com/pay'),
        isA<SharedPaymentNotice>(),
      );
      expect(
        resolveSharedText('https://${VizorDeepLink.host}/'),
        isA<SharedPaymentNotice>(),
      );
    });

    test('nothing usable gets the no-payment notice', () {
      expect(resolveSharedText('Hello world'), SharedPaymentNotice.noPayment);
    });
  });

  group('SharedPaymentIntake with an image', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shared_payment_intake');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<File> imageFile() =>
        File('${tempDir.path}/shared.png').writeAsBytes([0]);

    // The intake does not wait for the delete, so the check gives it a moment.
    Future<bool> isGone(File file) async {
      for (var attempt = 0; attempt < 50; attempt++) {
        if (!await file.exists()) return true;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return false;
    }

    SharedPaymentIntake intake(SharedImageQrCodes readQrCodes) =>
        SharedPaymentIntake(readQrCodes: readQrCodes);

    test('the one QR code in an image is resolved like shared text, and the '
        'copy is deleted', () async {
      final file = await imageFile();

      final outcome = await intake((path) async {
        expect(path, file.path);
        return [link];
      }).resolve(SharedImage(file.path, seq: 1));

      expect(
        outcome,
        isA<SharedPaymentRequest>().having((r) => r.raw, 'raw', link),
      );
      expect(await isGone(file), isTrue);
    });

    test(
      'an image with no code, with several, or none at all says so',
      () async {
        for (final (codes, notice) in [
          (<String>[], SharedPaymentNotice.imageNoCode),
          ([link, link], SharedPaymentNotice.imageSeveralCodes),
        ]) {
          final file = await imageFile();
          final outcome = await intake(
            (_) async => codes,
          ).resolve(SharedImage(file.path, seq: 1));
          expect(outcome, notice);
          expect(await isGone(file), isTrue);
        }
        expect(
          await intake(noCodes).resolve(const SharedUnreadableImage(seq: 1)),
          SharedPaymentNotice.imageUnreadable,
        );
      },
    );

    test(
      'a zcash: link in a QR code is handed on whole, whatever it holds',
      () {
        // A curly apostrophe or a raw space would end a link in prose; a QR
        // code holds no prose, so the lane gets the whole request to reject.
        const curly = 'zcash:$transparent?label=Tom’s&amount=1&memo=aGk';
        const spaced = 'zcash:$transparent?message=Coffee for two&amount=0.5';
        for (final code in [curly, spaced]) {
          expect(
            resolveSharedCode(code),
            isA<SharedPaymentRequest>().having((r) => r.raw, 'raw', code),
          );
        }
        expect(
          resolveSharedCode('Pay $transparent'),
          isA<SharedPaymentRequest>().having(
            (r) => r.raw,
            'raw',
            'zcash:$transparent',
          ),
        );
      },
    );

    test('a reader failure is reported as unreadable and still deletes the '
        'copy', () async {
      final file = await imageFile();

      final outcome = await intake(
        (_) async => throw StateError('plugin missing'),
      ).resolve(SharedImage(file.path, seq: 1));

      expect(outcome, SharedPaymentNotice.imageUnreadable);
      expect(await isGone(file), isTrue);
    });

    test('discarding an image share deletes its copy', () async {
      final file = await imageFile();

      intake(noCodes).discard(SharedImage(file.path, seq: 1));

      expect(await isGone(file), isTrue);
      // Nothing to delete is not an error.
      intake(noCodes).discard(const SharedUnreadableImage(seq: 1));
      intake(noCodes).discard(const SharedText('text', seq: 1));
    });
  });
}
