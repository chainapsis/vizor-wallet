// Lane-agnostic: no widgets, no metrics — only the request flow's rules.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/services/request_qr_export.dart';
import 'package:zcash_wallet/src/core/zcash/zip321_payment_request.dart';
import 'package:zcash_wallet/src/features/receive/services/zec_request_draft.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';

const _shielded =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const _transparent = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';

void main() {
  group('ZecRequestDraft', () {
    test('a ZEC amount becomes the request URI and its dollar line', () {
      const draft = ZecRequestDraft(address: _shielded, input: '0.5');
      final view = draft.resolve(zecUsdUnitPrice: 70);

      expect(view.requestUri, 'zcash:$_shielded?amount=0.5');
      expect(view.conversionText, r'$ 35.00');
      expect(view.amountError, isNull);
      expect(view.isReady, isTrue);
    });

    test('a USD amount converts into the ZEC the request encodes', () {
      const draft = ZecRequestDraft(
        address: _shielded,
        input: '35',
        inputIsUsd: true,
      );
      final view = draft.resolve(zecUsdUnitPrice: 70);

      expect(view.amountZec, '0.5');
      expect(view.fieldText, '35');
      expect(view.conversionText, '0.5 ZEC');
      expect(view.requestUri, 'zcash:$_shielded?amount=0.5');
    });

    test('the dollar line waits rather than guessing without a price', () {
      const draft = ZecRequestDraft(address: _shielded, input: '0.5');

      expect(draft.resolve(zecUsdUnitPrice: null).conversionText, isNull);
      // With nothing typed there is nothing to wait for.
      expect(
        const ZecRequestDraft(
          address: _shielded,
        ).resolve(zecUsdUnitPrice: null).conversionText,
        r'$ 0',
      );
    });

    test('only actionable amount rejections surface as errors', () {
      String? errorFor(String input) => ZecRequestDraft(
        address: _shielded,
        input: input,
      ).resolve(zecUsdUnitPrice: 70).amountError;

      expect(errorFor('0.123456789'), kRequestAmountDecimalsError);
      expect(errorFor('21000001'), kRequestAmountSupplyError);
      // In-progress input is not a failure state.
      expect(errorFor('0.'), isNull);
      expect(errorFor(''), isNull);
      expect(errorFor('0'), isNull);
      expect(errorFor('.'), isNull);
      expect(errorFor('0.00'), isNull);
    });

    test('an amount that is not a number says so instead of going quiet', () {
      String? errorFor(String input) => ZecRequestDraft(
        address: _shielded,
        input: input,
      ).resolve(zecUsdUnitPrice: 70).amountError;

      // The comma a French or German decimal keypad emits, and the leading
      // dot the conversion line happily prices: both build a URI of null, so
      // silence here is a permanently disabled CTA with no cause on screen.
      expect(errorFor('0,5'), kRequestAmountFormatError);
      expect(errorFor('.5'), kRequestAmountFormatError);
      expect(errorFor('1e3'), kRequestAmountFormatError);
      expect(errorFor('half a zec'), kRequestAmountFormatError);
    });

    test('switching units rewrites the field in the new unit', () {
      const zecDraft = ZecRequestDraft(address: _shielded, input: '0.5');
      final usdDraft = zecDraft.toggledUnit(zecUsdUnitPrice: 70);
      expect(usdDraft.inputIsUsd, isTrue);
      expect(usdDraft.input, '35.00');

      final backToZec = usdDraft.toggledUnit(zecUsdUnitPrice: 70);
      expect(backToZec.inputIsUsd, isFalse);
      expect(backToZec.input, '0.5');
    });

    test('a unit switch never changes the ZEC the request asks for', () {
      // $35.123 does not divide 0.5 ZEC into whole cents: the field shows
      // the rounding, the request must keep the number that was typed.
      const price = 35.123;
      const zecDraft = ZecRequestDraft(address: _shielded, input: '0.5');
      final usdDraft = zecDraft.toggledUnit(zecUsdUnitPrice: price);
      expect(usdDraft.input, '17.56');

      final view = usdDraft.resolve(zecUsdUnitPrice: price);
      expect(view.amountZec, '0.5');
      expect(view.conversionText, '0.5 ZEC');
      expect(view.requestUri, 'zcash:$_shielded?amount=0.5');

      // The market moves while the derived dollars are on screen: they still
      // stand for the ZEC that was typed, so the request does not drift.
      expect(usdDraft.resolve(zecUsdUnitPrice: 40).amountZec, '0.5');

      final backToZec = usdDraft.toggledUnit(zecUsdUnitPrice: price);
      expect(backToZec.input, '0.5');
      expect(
        backToZec.resolve(zecUsdUnitPrice: price).requestUri,
        'zcash:$_shielded?amount=0.5',
      );
    });

    test('derived dollars stay creatable after the price expires', () {
      final usdDraft = const ZecRequestDraft(
        address: _shielded,
        input: '0.5',
      ).toggledUnit(zecUsdUnitPrice: 70);

      // The dollars on screen came from 0.5 ZEC; losing the price does not
      // lose that.
      final view = usdDraft.resolve(zecUsdUnitPrice: null);
      expect(view.amountZec, '0.5');
      expect(view.conversionText, '0.5 ZEC');
      expect(view.isReady, isTrue);
      expect(view.requestUri, 'zcash:$_shielded?amount=0.5');

      // Typed dollars are dollars, and dollars need a price.
      final typed = usdDraft.withInput('40', zecUsdUnitPrice: 70);
      expect(typed.resolve(zecUsdUnitPrice: null).amountZec, '');
      expect(typed.resolve(zecUsdUnitPrice: null).isReady, isFalse);
    });

    test('a ZEC amount below a cent stays in ZEC', () {
      // 0.00000001 ZEC at \$70 is \$0.0000007: the dollar field would round it
      // to nothing while the request kept encoding the amount, so the switch
      // is refused rather than taken.
      const draft = ZecRequestDraft(address: _shielded, input: '0.00000001');

      expect(draft.canToggleUnit(70), isFalse);
      final same = draft.toggledUnit(zecUsdUnitPrice: 70);
      expect(same.inputIsUsd, isFalse);
      expect(same.input, '0.00000001');
      expect(
        same.resolve(zecUsdUnitPrice: 70).requestUri,
        'zcash:$_shielded?amount=0.00000001',
      );

      // An amount that does have a cent form still switches.
      const payable = ZecRequestDraft(address: _shielded, input: '0.5');
      expect(payable.canToggleUnit(70), isTrue);
    });

    test('switching an unfinished ZEC field to USD derives nothing', () {
      for (final input in ['', '0', '0.', 'abc']) {
        final usdDraft = ZecRequestDraft(
          address: _shielded,
          input: input,
        ).toggledUnit(zecUsdUnitPrice: 70);
        final view = usdDraft.resolve(zecUsdUnitPrice: null);
        expect(usdDraft.input, '', reason: input);
        expect(view.amountZec, '', reason: input);
        expect(view.isReady, isFalse, reason: input);
        expect(view.amountError, isNull, reason: input);
      }
    });

    test('an edited USD field re-derives the ZEC the request asks for', () {
      const price = 35.123;
      final usdDraft = const ZecRequestDraft(address: _shielded, input: '0.5')
          .toggledUnit(zecUsdUnitPrice: price)
          .withInput('20', zecUsdUnitPrice: price);

      // Typed dollars mean dollars: the carried ZEC follows the field.
      final view = usdDraft.resolve(zecUsdUnitPrice: price);
      expect(view.amountZec, usdDraft.zecInput);
      expect(view.amountZec, isNot('0.5'));
      expect(view.requestUri, 'zcash:$_shielded?amount=${view.amountZec}');

      // Text that does not convert encodes nothing, whatever was carried.
      expect(
        usdDraft
            .withInput('abc', zecUsdUnitPrice: price)
            .resolve(zecUsdUnitPrice: price)
            .amountZec,
        '',
      );
    });

    test('USD mode is refused while there is no price to convert at', () {
      const draft = ZecRequestDraft(address: _shielded, input: '0.5');
      expect(draft.canToggleUnit(null), isFalse);
      expect(draft.toggledUnit(zecUsdUnitPrice: null).inputIsUsd, isFalse);

      // Leaving USD mode never needs a price.
      const usdDraft = ZecRequestDraft(
        address: _shielded,
        input: '35',
        inputIsUsd: true,
      );
      expect(usdDraft.canToggleUnit(null), isTrue);
    });

    test('a price that expires mid-compose does not erase the amount', () {
      const zecDraft = ZecRequestDraft(address: _shielded, input: '0.5');
      final usdDraft = zecDraft.toggledUnit(zecUsdUnitPrice: 70);
      expect(usdDraft.input, '35.00');

      // The price goes away while the sheet is open: the switch is still
      // offered, and taking it hands back the ZEC that was typed.
      final backToZec = usdDraft.toggledUnit(zecUsdUnitPrice: null);
      expect(backToZec.inputIsUsd, isFalse);
      expect(backToZec.input, '0.5');
      expect(backToZec.resolve(zecUsdUnitPrice: null).isReady, isTrue);
    });

    test('USD keystrokes keep the canonical ZEC in step', () {
      final usdDraft = const ZecRequestDraft(
        address: _shielded,
        input: '0.5',
      ).toggledUnit(zecUsdUnitPrice: 70).withInput('70', zecUsdUnitPrice: 70);

      expect(usdDraft.input, '70');
      expect(usdDraft.zecInput, '1');

      // Edited at the live price, switched back without one: the restored
      // value is what the dollars last meant, not what they meant on entry.
      expect(usdDraft.toggledUnit(zecUsdUnitPrice: null).input, '1');
    });

    test('clearing a USD field clears what a switch back would restore', () {
      final cleared = const ZecRequestDraft(
        address: _shielded,
        input: '0.5',
      ).toggledUnit(zecUsdUnitPrice: 70).withInput('', zecUsdUnitPrice: 70);

      expect(cleared.zecInput, '');
      expect(cleared.toggledUnit(zecUsdUnitPrice: null).input, '');
    });

    test('a ZEC keystroke is its own canonical value', () {
      final draft = const ZecRequestDraft(
        address: _shielded,
      ).withInput('0.25', zecUsdUnitPrice: null);

      expect(draft.zecInput, '0.25');
      expect(draft.resolve(zecUsdUnitPrice: null).amountZec, '0.25');
    });

    test('a pasted bidi override never reaches the request link', () {
      final view = const ZecRequestDraft(
        address: _shielded,
        input: '0.5',
      ).copyWith(message: 'Table\u202E 4').resolve(zecUsdUnitPrice: null);

      final uri = view.requestUri;

      expect(uri, isNotNull);

      final parsed = Zip321PaymentRequest.parse(uri!);

      expect(parsed.primaryPayment.memoText, 'Table 4');
    });

    test('a transparent request drops the message it cannot carry', () {
      const draft = ZecRequestDraft(
        address: _transparent,
        input: '0.5',
        message: 'Table 4',
      );
      final view = draft.resolve(zecUsdUnitPrice: 70);

      expect(draft.isShielded, isFalse);
      expect(view.effectiveMessage, isNull);
      expect(view.requestUri, 'zcash:$_transparent?amount=0.5');
    });
  });

  group('request QR export', () {
    test('names the file after the amount, or nothing when there is none', () {
      expect(requestQrFileName('0.5'), 'vizor-request-0.5.png');
      expect(requestQrFileName(''), 'vizor-request.png');
      expect(requestQrFileName('1 ZEC'), 'vizor-request-1.png');
    });

    test('writes the PNG where the save dialog pointed it', () async {
      final directory = await Directory.systemTemp.createTemp('vizor-request');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final bytes = Uint8List.fromList([1, 2, 3]);
      final suggested = <String>[];
      final saved = await saveRequestQrPng(
        png: bytes,
        amountZec: '0.5',
        pickSaveLocation: ({required String suggestedName}) async {
          suggested.add(suggestedName);
          return '${directory.path}${Platform.pathSeparator}chosen.png';
        },
      );

      expect(suggested, ['vizor-request-0.5.png']);
      expect(saved, isNotNull);
      expect(saved!.path, endsWith('chosen.png'));
      expect(
        saved.folderName,
        directory.path.split(Platform.pathSeparator).last,
      );
      expect(File(saved.path).readAsBytesSync(), bytes);
    });

    test('replaces a file the user chose to overwrite', () async {
      final directory = await Directory.systemTemp.createTemp('vizor-request');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final path = '${directory.path}${Platform.pathSeparator}chosen.png';
      File(path).writeAsBytesSync(Uint8List.fromList([9, 9, 9]));

      final bytes = Uint8List.fromList([1, 2, 3]);
      final saved = await saveRequestQrPng(
        png: bytes,
        amountZec: '0.5',
        pickSaveLocation: ({required String suggestedName}) async => path,
      );

      expect(saved?.path, path);
      expect(File(path).readAsBytesSync(), bytes);
    });

    test('writes nothing when the save dialog was cancelled', () async {
      final directory = await Directory.systemTemp.createTemp('vizor-request');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final saved = await saveRequestQrPng(
        png: Uint8List.fromList([1, 2, 3]),
        amountZec: '0.5',
        pickSaveLocation: ({required String suggestedName}) async => null,
      );

      expect(saved, isNull);
      expect(directory.listSync(), isEmpty);
    });
  });
}
