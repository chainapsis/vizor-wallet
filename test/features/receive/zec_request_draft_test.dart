// Lane-agnostic: no widgets, no metrics — only the request flow's rules.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/services/request_qr_export.dart';
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

    test('writes the PNG and never overwrites an earlier one', () async {
      final directory = await Directory.systemTemp.createTemp('vizor-request');
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });

      final bytes = Uint8List.fromList([1, 2, 3]);
      final first = await saveRequestQrPng(
        png: bytes,
        amountZec: '0.5',
        resolveDirectory: () async => directory,
      );
      final second = await saveRequestQrPng(
        png: bytes,
        amountZec: '0.5',
        resolveDirectory: () async => directory,
      );

      expect(first.path, endsWith('vizor-request-0.5.png'));
      expect(second.path, endsWith('vizor-request-0.5-2.png'));
      expect(
        first.folderName,
        directory.path.split(Platform.pathSeparator).last,
      );
      expect(File(first.path).readAsBytesSync(), bytes);
    });
  });
}
