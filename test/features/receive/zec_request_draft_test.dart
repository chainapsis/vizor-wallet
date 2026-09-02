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
