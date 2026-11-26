import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/navigation/shared_payment_intake.dart';
import 'package:zcash_wallet/src/core/navigation/vizor_deep_link.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';
import 'package:zcash_wallet/src/services/shared_payment_service.dart';

void main() {
  const transparent = 'tmEjY6KfCryQhJ1hKSGiA7p8EeVggpvN78r';
  const unified =
      'u1qpzry9x8gf2tvdw0s3jn54khce6mua7lqpzry9x8gf2tvdw0s3jn54khce6mua7l';
  const regtest =
      'uregtest1qpzry9x8gf2tvdw0s3jn54khce6mua7lqpzry9x8gf2tvdw0s3jn54khce6';
  const request = 'zcash:$unified?amount=0.5';
  final gift = 'https://${VizorDeepLink.host}/payment-links/open#v1=abcdef';

  test('accepts complete addresses and only trims surrounding whitespace', () {
    for (final address in [
      transparent,
      unified,
      regtest,
      unified.toUpperCase(),
    ]) {
      final outcome =
          resolveSharedText(' \n$address\t ') as SharedPaymentRequest;
      expect(outcome.raw, 'zcash:$address');
    }
    for (final text in [
      '',
      'hello',
      '${transparent}x',
      transparent.substring(1),
    ]) {
      expect(resolveSharedText(text), SharedPaymentNotice.noPayment);
    }
  });

  test('encoded label, amount, message, and memo survive unchanged', () {
    const raw =
        'zcash:$unified?label=Coffee%20for%20two&amount=0.5'
        '&message=Pay%20now%20please&memo=aGk_';
    final outcome = resolveSharedText(raw) as SharedPaymentRequest;
    expect(outcome.raw, raw);
    final payment = Zip321PaymentRequest.parse(outcome.raw).primaryPayment;
    expect(payment.label, 'Coffee for two');
    expect(payment.amount, '0.5');
    expect(payment.message, 'Pay now please');
    expect(payment.memoText, 'hi?');
  });

  test(
    'percent-encoded Unicode is accepted and decoded by the ZIP-321 parser',
    () {
      const raw = 'zcash:$unified?label=%E5%92%96%E5%95%A1&amount=1';
      final outcome = resolveSharedText(raw) as SharedPaymentRequest;
      expect(outcome.raw, raw);
      expect(
        Zip321PaymentRequest.parse(outcome.raw).primaryPayment.label,
        '咖啡',
      );
    },
  );

  test('does not strip punctuation belonging to complete query values', () {
    for (final value in ['Paid!', '(a)', "Bob's", 'a*']) {
      final raw = 'zcash:$unified?amount=1&label=$value';
      expect((resolveSharedText(raw) as SharedPaymentRequest).raw, raw);
      expect(Zip321PaymentRequest.parse(raw).primaryPayment.label, value);
    }
  });

  test('accepts only a complete Gift Card URL on the configured origin', () {
    expect(
      resolveSharedText(' \n$gift\t '),
      isA<SharedGiftCard>().having((g) => g.link, 'link', gift),
    );
    for (final text in [
      'https://example.com/payment-links/open#v1=abcdef',
      'https://${VizorDeepLink.host}/unknown/$transparent',
      'https://${VizorDeepLink.host}/unknown/咖啡/$unified',
      'https://${VizorDeepLink.host}/',
      'https://explorer.example/address/$transparent',
    ]) {
      expect(resolveSharedText(text), SharedPaymentNotice.noPayment);
    }
  });

  test(
    'prose, wrappers, captions, and multiple values are never extracted',
    () {
      for (final text in [
        'Pay $transparent',
        'Pay $request',
        'Pay “$request”',
        "Pay '$request' if that's convenient",
        '($request)',
        '**$request**',
        'Here is your gift: $gift',
        'Vizor Gift Card\n\n$gift',
        '$transparent $unified',
        '$gift\n$gift',
        'Pay zcash:$unified?label=。&amount=1',
        'Pay “zcash:$unified?label=Coffee for two&amount=1 0”',
      ]) {
        expect(
          resolveSharedText(text),
          SharedPaymentNotice.noPayment,
          reason: text,
        );
      }
    },
  );

  test(
    'raw spaces, controls, and Unicode reject complete payment payloads',
    () {
      for (final text in [
        'zcash:$unified?label=Coffee for two&amount=0.5',
        'zcash:$unified?amount=1 0',
        'zcash:$unified?label=。&amount=1',
        'zcash:$unified?label=咖啡&amount=1&memo=aGk',
        'zcash:$unified?label=Coffee☕&amount=1',
        'zcash:$unified?label=Tom’s&amount=1',
        '$request\nSent from another app',
        '$request\n$request',
        'zcash:$unified?amount=1\t0',
        'zcash:$unified?amount=1\u00000',
      ]) {
        expect(
          resolveSharedText(text),
          SharedPaymentNotice.malformedPayment,
          reason: text,
        );
      }
    },
  );

  test(
    'ASCII malformed amounts, memos, and required conditions stay whole',
    () {
      for (final raw in [
        'zcash:$unified?label=Coffee%20for%20two&req-foo+bar=x',
        'zcash:$unified?req-foo+bar',
        'zcash:$unified?req-foo%2Bbar=x',
        'zcash:$unified?amount=1%200',
        'zcash:$unified?amount=1&memo=aGk_?',
        'zcash:$unified?amount=1&amount=2',
        'zcash:not-an-address?amount=x',
      ]) {
        final outcome = resolveSharedText(raw) as SharedPaymentRequest;
        expect(outcome.raw, raw);
        expect(
          () => Zip321PaymentRequest.parse(outcome.raw),
          throwsA(anything),
        );
      }
    },
  );

  group('shared QR images', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shared_payment_intake');
    });
    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
    Future<File> copy() => File('${tempDir.path}/shared.png').writeAsBytes([0]);
    Future<void> expectDeleted(File file) async {
      for (var attempt = 0; attempt < 50 && await file.exists(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await file.exists(), isFalse);
    }

    test(
      'uses the same complete-payload rule as text and deletes its copy',
      () async {
        for (final code in [
          transparent,
          request,
          gift,
          'Pay $transparent',
          'zcash:$unified?amount=1 0',
          '$request\nSent from another app',
        ]) {
          final file = await copy();
          final outcome = await SharedPaymentIntake(
            readQrCodes: (_) async => [code],
          ).resolve(SharedImage(file.path, seq: 1));
          final textOutcome = resolveSharedText(code);
          expect(outcome.runtimeType, textOutcome.runtimeType);
          if (outcome is SharedPaymentRequest &&
              textOutcome is SharedPaymentRequest) {
            expect(outcome.raw, textOutcome.raw);
          } else if (outcome is SharedGiftCard &&
              textOutcome is SharedGiftCard) {
            expect(outcome.link, textOutcome.link);
          } else {
            expect(outcome, textOutcome);
          }
          await expectDeleted(file);
        }
      },
    );

    test('refuses zero or multiple codes and deletes the image', () async {
      for (final (codes, notice) in [
        (<String>[], SharedPaymentNotice.imageNoCode),
        ([request, request], SharedPaymentNotice.imageSeveralCodes),
        ([request, ''], SharedPaymentNotice.imageSeveralCodes),
      ]) {
        final file = await copy();
        final outcome = await SharedPaymentIntake(
          readQrCodes: (_) async => codes,
        ).resolve(SharedImage(file.path, seq: 1));
        expect(outcome, notice);
        await expectDeleted(file);
      }
    });

    test(
      'reader failures and unreadable images keep the existing notice',
      () async {
        final file = await copy();
        final intake = SharedPaymentIntake(
          readQrCodes: (_) async => throw StateError('reader failed'),
        );
        expect(
          await intake.resolve(SharedImage(file.path, seq: 1)),
          SharedPaymentNotice.imageUnreadable,
        );
        await expectDeleted(file);
        expect(
          await intake.resolve(const SharedUnreadableImage(seq: 1)),
          SharedPaymentNotice.imageUnreadable,
        );
      },
    );

    test('discarding an image still deletes its copy', () async {
      final file = await copy();
      SharedPaymentIntake(
        readQrCodes: (_) async => [],
      ).discard(SharedImage(file.path, seq: 1));
      await expectDeleted(file);
    });
  });
}
