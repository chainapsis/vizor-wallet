// Lane-agnostic: this file runs in the plain desktop lane and, with the
// mobile define, in the mobile lane. Nothing here asserts a literal metric —
// only token constants, copy and structure, all of which hold in both.

import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors, Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/pool_badge.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_card.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_sheet.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';

const _shielded =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const _transparent = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';
const _message = 'Table 4 — two flat whites';

const _empty = ZecRequestView(address: _shielded);
const _withAmount = ZecRequestView(
  address: _shielded,
  amountZec: '0.5',
  conversionText: r'$35.00',
);
const _withMessage = ZecRequestView(
  address: _shielded,
  amountZec: '0.5',
  conversionText: r'$35.00',
  messageText: _message,
);
const _transparentRequest = ZecRequestView(
  address: _transparent,
  amountZec: '0.5',
  conversionText: r'$35.00',
);

/// ZEC typed with no live price to convert it.
const _priceUnavailable = ZecRequestView(address: _shielded, amountZec: '0.5');

const _withError = ZecRequestView(
  address: _shielded,
  amountDisplayText: '0.123456789',
  amountError: kRequestAmountDecimalsError,
);

/// Text the ZIP-321 builder cannot read as a number at all.
const _withFormatError = ZecRequestView(
  address: _shielded,
  amountDisplayText: '0,5',
  amountError: kRequestAmountFormatError,
);

/// The field collecting dollars, so its formatters cap at cents.
const _usdMode = ZecRequestView(
  address: _shielded,
  amountInputIsUsd: true,
  conversionText: '0 ZEC',
);

void main() {
  group('ZecRequestView', () {
    test('an empty amount encodes the plain address, not a request', () {
      expect(_empty.qrData, _shielded);
      expect(_empty.requestUri, isNull);
      expect(_empty.isReady, isFalse);
      expect(_empty.summaryAmountText, isNull);
    });

    test('an amount turns the address QR into a request QR', () {
      expect(_withAmount.qrData, startsWith('zcash:$_shielded?amount=0.5'));
      expect(_withAmount.isReady, isTrue);
      expect(_withAmount.summaryAmountText, '0.5 ZEC');
    });

    test('a transparent request drops the message entirely', () {
      const withStaleMessage = ZecRequestView(
        address: _transparent,
        amountZec: '0.5',
        messageText: _message,
      );

      expect(withStaleMessage.effectiveMessage, isNull);
      expect(withStaleMessage.requestUri, isNot(contains('memo=')));
    });

    test('an unusable amount is not a request yet, and is not an error', () {
      expect(_withError.requestUri, isNull);
      expect(_withError.qrData, _shielded);
    });

    test('the share text is null until there is a request to share', () {
      expect(_empty.shareText, isNull);
      expect(_withError.shareText, isNull);
      expect(_withAmount.shareText, startsWith('Pay me 0.5 ZEC with Vizor\n'));
    });

    test('the share text names the amount and carries the link', () {
      expect(
        buildRequestShareText(amountZec: '0.5', uri: 'zcash:$_shielded'),
        'Pay me 0.5 ZEC with Vizor\nzcash:$_shielded',
      );
    });
  });

  group('desktop request modal step one', () {
    testWidgets('empty amount shows no QR and a disabled Next', (tester) async {
      await _pump(tester, const RequestAmountCard(request: _empty));

      expect(tester.takeException(), isNull);
      expect(find.text(kRequestFlowTitle), findsOneWidget);
      // The artefact belongs to step two: nothing here is a request yet.
      expect(find.byType(RequestQrSurface), findsNothing);
      // No error while the field is simply still empty.
      expect(
        find.byKey(const ValueKey('request_amount_error_text')),
        findsNothing,
      );
      expect(find.byType(RequestSummaryRow), findsNothing);
      expect(find.text('Create request'), findsOneWidget);
      expect(_button(tester, 'request_next_button').onPressed, isNull);
      expect(find.byKey(const ValueKey('request_modal_back')), findsNothing);
    });

    testWidgets('no live price shows the loading pill, not a number', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountCard(
          request: _priceUnavailable,
          onToggleAmountUnit: null,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('request_amount_price_loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('request_amount_conversion_text')),
        findsNothing,
      );
      expect(find.text(r'$ 0'), findsNothing);
      // Next still works: the request is in ZEC and needs no conversion.
      expect(_button(tester, 'request_next_button').onPressed, isNotNull);
    });

    testWidgets('an amount enables Create request', (tester) async {
      var advanced = 0;
      await _pump(
        tester,
        RequestAmountCard(request: _withAmount, onNext: () => advanced++),
      );

      expect(tester.takeException(), isNull);
      // One label for one commitment, on both form factors.
      expect(find.text('Create request'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(_button(tester, 'request_next_button').onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('request_next_button')));
      await tester.pump();
      expect(advanced, 1);
    });

    testWidgets('the message prompt says the link is readable, not encrypted', (
      tester,
    ) async {
      await _pump(tester, const RequestAmountCard(request: _empty));

      // The request memo rides in the shareable link, so the send composer's
      // "Encrypted" promise must not be repeated here.
      expect(
        kRequestMessageHelpText,
        'Shielded addresses only — anyone with this link can read it.',
      );
      expect(find.text(kRequestMessageHelpText), findsOneWidget);
      expect(find.textContaining('Encrypted'), findsNothing);
    });

    testWidgets('the expanded message hints who can read it', (tester) async {
      await _pump(
        tester,
        const RequestAmountCard(request: _empty, messageExpanded: true),
      );

      expect(
        find.text('Anyone you send the link to can read this'),
        findsOneWidget,
      );
      expect(find.text('Only the recipient can read this'), findsNothing);
    });

    testWidgets('the expanded message carries the byte counter', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountCard(request: _withMessage, messageExpanded: true),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('request_message_field')),
        findsOneWidget,
      );
      expect(_text(tester, 'request_message_counter'), endsWith('/512'));
      expect(find.text(kRequestAddMessageLabel), findsNothing);
    });

    testWidgets('a transparent request offers no message at all', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountCard(request: _transparentRequest),
      );

      expect(tester.takeException(), isNull);
      // Absent, not disabled: a transparent memo can never be sent.
      expect(
        find.byKey(const ValueKey('request_add_message_card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('request_message_field')), findsNothing);
    });

    testWidgets('an invalid amount errors inline and blocks the action', (
      tester,
    ) async {
      await _pump(tester, const RequestAmountCard(request: _withError));

      expect(tester.takeException(), isNull);
      expect(
        _text(tester, 'request_amount_error_text'),
        kRequestAmountDecimalsError,
      );
      expect(_button(tester, 'request_next_button').onPressed, isNull);
      expect(find.byType(RequestSummaryRow), findsNothing);
    });

    testWidgets('an amount the builder cannot read says what to type', (
      tester,
    ) async {
      await _pump(tester, const RequestAmountCard(request: _withFormatError));

      expect(
        _text(tester, 'request_amount_error_text'),
        kRequestAmountFormatError,
      );
      expect(_button(tester, 'request_next_button').onPressed, isNull);
    });

    testWidgets('the amount field normalises a comma to a decimal point', (
      tester,
    ) async {
      final typed = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountCard(
          request: _empty,
          amountController: controller,
          onAmountChanged: typed.add,
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_field')),
        '0,5',
      );
      await tester.pump();

      expect(controller.text, '0.5');
      expect(typed.last, '0.5');
    });

    testWidgets('the amount field stops at a zatoshi', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountCard(request: _empty, amountController: controller),
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_field')),
        '0.123456789',
      );
      await tester.pump();

      expect(controller.text, '0.12345678');
    });

    testWidgets('the amount field refuses what is not part of a number', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountCard(request: _empty, amountController: controller),
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_field')),
        '.5 ZEC',
      );
      await tester.pump();

      // The leading dot is completed rather than dropped, and the letters
      // that would have made the URI unbuildable never land.
      expect(controller.text, '0.5');
    });

    testWidgets('a USD-mode field stops at cents', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountCard(request: _usdMode, amountController: controller),
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_field')),
        '35,499',
      );
      await tester.pump();

      expect(controller.text, '35.49');
    });
  });

  group('desktop request modal step two', () {
    testWidgets('shows the request QR, its summary and a way back', (
      tester,
    ) async {
      var back = 0;
      await _pump(
        tester,
        RequestResultCard(request: _withAmount, onBack: () => back++),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(kRequestFlowTitle), findsOneWidget);
      expect(find.byType(RequestQrSurface), findsOneWidget);
      expect(find.text('0.5 ZEC'), findsOneWidget);
      expect(find.text('Shielded'), findsOneWidget);
      expect(find.byType(PoolBadge), findsOneWidget);
      // The link itself is carried by the actions, not printed under the QR.
      expect(find.byKey(const ValueKey('request_uri_line')), findsNothing);
      expect(_button(tester, 'request_copy_link_button').onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('request_modal_back')));
      await tester.pump();
      expect(back, 1);
    });

    testWidgets('a transparent request states its pool', (tester) async {
      await _pump(
        tester,
        const RequestResultCard(request: _transparentRequest),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Transparent'), findsOneWidget);
    });

    testWidgets('saving the QR hands the caller PNG bytes once', (
      tester,
    ) async {
      final saved = <Uint8List>[];
      await _pump(
        tester,
        RequestResultCard(request: _withAmount, onSaveQrImage: saved.add),
      );

      await tester.tap(find.byKey(const ValueKey('request_save_qr_button')));
      await tester.pump();
      // While the encode is in flight the button is inert, so a second tap
      // cannot start a second one.
      expect(_exportButton(tester, 'request_save_qr_button').onPressed, isNull);

      await _settleEncode(tester);

      expect(saved, hasLength(1));
      expect(saved.single.sublist(0, 8), _pngSignature);
      expect(
        _exportButton(tester, 'request_save_qr_button').onPressed,
        isNotNull,
      );
    }, timeout: _encodeTimeout);

    testWidgets('an empty request cannot be saved as an image', (tester) async {
      await _pump(
        tester,
        RequestResultCard(request: _empty, onSaveQrImage: (_) {}),
      );

      expect(_exportButton(tester, 'request_save_qr_button').onPressed, isNull);
      expect(_button(tester, 'request_copy_link_button').onPressed, isNull);
    });
  });

  group('mobile request sheet', () {
    testWidgets('no live price shows the loading pill, not a number', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(
          request: _priceUnavailable,
          onToggleAmountUnit: null,
        ),
        size: _mobileSize,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('request_amount_price_loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('request_amount_conversion_text')),
        findsNothing,
      );
      expect(find.text(r'$ 0'), findsNothing);
    });

    testWidgets('step one gates the CTA on a usable amount', (tester) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(request: _empty),
        size: _mobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(kRequestFlowTitle), findsOneWidget);
      expect(find.text('Create request'), findsOneWidget);
      expect(_button(tester, 'request_create_button').onPressed, isNull);
      // No Max: a request is not a spend.
      expect(find.text('Max'), findsNothing);
    });

    testWidgets('step one shows the message it will attach', (tester) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(request: _withMessage),
        size: _mobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(_button(tester, 'request_create_button').onPressed, isNotNull);
      expect(_text(tester, 'request_message_preview'), _message);
    });

    testWidgets('step one hides the message row for a transparent address', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(request: _transparentRequest),
        size: _mobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('request_message_row')), findsNothing);
    });

    testWidgets('an invalid amount states the correction to make', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(request: _withError),
        size: _mobileSize,
      );

      expect(tester.takeException(), isNull);
      // Red digits alone say something is wrong without saying what, and the
      // two causes need opposite fixes.
      expect(
        _text(tester, 'request_amount_error_text'),
        kRequestAmountDecimalsError,
      );
      expect(_button(tester, 'request_create_button').onPressed, isNull);
    });

    testWidgets('a valid amount shows no error row', (tester) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(request: _withAmount),
        size: _mobileSize,
      );

      expect(
        find.byKey(const ValueKey('request_amount_error_text')),
        findsNothing,
      );
    });

    testWidgets('the serif field normalises a comma-decimal keypad', (
      tester,
    ) async {
      final typed = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountSheetCompose(
          request: _empty,
          amountController: controller,
          onAmountChanged: typed.add,
        ),
        size: _mobileSize,
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_input')),
        '0,5',
      );
      await tester.pump();

      expect(controller.text, '0.5');
      expect(typed.last, '0.5');
    });

    testWidgets('the serif field stops at a zatoshi', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountSheetCompose(
          request: _empty,
          amountController: controller,
        ),
        size: _mobileSize,
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_input')),
        '0.123456789',
      );
      await tester.pump();

      expect(controller.text, '0.12345678');
    });

    testWidgets('a USD-mode serif field stops at cents', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        RequestAmountSheetCompose(
          request: _usdMode,
          amountController: controller,
        ),
        size: _mobileSize,
      );

      await tester.enterText(
        find.byKey(const ValueKey('request_amount_input')),
        '35,499',
      );
      await tester.pump();

      expect(controller.text, '35.49');
    });

    testWidgets('an untakeable unit switch is drawn as disabled', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountSheetCompose(
          request: _priceUnavailable,
          onToggleAmountUnit: null,
        ),
        size: _mobileSize,
      );

      final colors = AppThemeData.dark.colors;
      final icon = tester.widget<AppIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('request_amount_mode_toggle')),
          matching: find.byType(AppIcon),
        ),
      );
      expect(icon.color, colors.icon.disabled);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('request_amount_mode_toggle')),
                matching: find.text(r'$'),
              ),
            )
            .style
            ?.color,
        colors.text.disabled,
      );
    });

    testWidgets('a takeable unit switch keeps its live colours', (
      tester,
    ) async {
      await _pump(
        tester,
        RequestAmountSheetCompose(
          request: _withAmount,
          onToggleAmountUnit: () {},
        ),
        size: _mobileSize,
      );

      final colors = AppThemeData.dark.colors;
      final icon = tester.widget<AppIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('request_amount_mode_toggle')),
          matching: find.byType(AppIcon),
        ),
      );
      expect(icon.color, colors.text.secondary);
      expect(
        _textStyle(tester, 'request_amount_conversion_text').color,
        colors.text.secondary,
      );
    });

    testWidgets('step two offers share, copy and a way back', (tester) async {
      await _pump(
        tester,
        const RequestAmountSheetResult(request: _withMessage),
        size: _mobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(RequestQrSurface), findsOneWidget);
      expect(find.text('0.5 ZEC'), findsOneWidget);
      expect(find.text('Shielded'), findsOneWidget);
      expect(find.text('Share request'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.byKey(const ValueKey('request_uri_line')), findsNothing);
      expect(find.byKey(const ValueKey('request_sheet_back')), findsOneWidget);
    });

    testWidgets('sharing hands over both the message and the PNG', (
      tester,
    ) async {
      String? sharedText;
      Uint8List? sharedPng;
      await _pump(
        tester,
        RequestAmountSheetResult(
          request: _withMessage,
          onShareRequest: (text, png) {
            sharedText = text;
            sharedPng = png;
          },
        ),
        size: _mobileSize,
      );

      await tester.tap(find.byKey(const ValueKey('request_share_button')));
      await tester.pump();
      await _settleEncode(tester);

      expect(sharedText, _withMessage.shareText);
      expect(sharedPng, isNotNull);
      expect(sharedPng!.sublist(0, 8), _pngSignature);
    }, timeout: _encodeTimeout);

    testWidgets('step two reports a transparent request as transparent', (
      tester,
    ) async {
      await _pump(
        tester,
        const RequestAmountSheetResult(request: _transparentRequest),
        size: _mobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Transparent'), findsOneWidget);
    });
  });

  group('renderRequestQrPng', () {
    testWidgets('encodes a request as a deterministic square PNG', (
      tester,
    ) async {
      final uri = _withAmount.requestUri!;
      await tester.runAsync(() async {
        final png = await renderRequestQrPng(uri, size: 256);
        final again = await renderRequestQrPng(uri, size: 256);

        expect(png, isNotEmpty);
        expect(png.sublist(0, 8), _pngSignature);
        // Same request, same bytes: nothing theme- or time-dependent leaks in.
        expect(again, png);

        final decoded = await decodeImageFromList(png);
        expect(decoded.width, 256);
        expect(decoded.height, 256);
        decoded.dispose();
      });
    }, timeout: _encodeTimeout);

    testWidgets('refuses an empty request rather than encoding nothing', (
      tester,
    ) async {
      await expectLater(renderRequestQrPng(''), throwsArgumentError);
    });
  });
}

/// Encoding a QR is real async work off the fake-async clock, so these tests
/// must not be able to hang the whole file for the default ten minutes.
const _encodeTimeout = Timeout(Duration(seconds: 30));

/// The eight bytes every PNG starts with.
const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

const _desktopSize = Size(900, 1000);
const _mobileSize = Size(393, 852);

AppButton _button(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey(key)));

/// The [AppButton] inside a [RequestQrExportButton], which owns the key.
AppButton _exportButton(WidgetTester tester, String key) =>
    tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AppButton),
      ),
    );

/// Lets an in-flight PNG encode finish: it runs on real time, which the
/// widget tester's fake clock never advances on its own.
Future<void> _settleEncode(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

TextStyle _textStyle(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).style!;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = _desktopSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            // The modal card is presented inside a Material surface in the
            // app; the text fields need that ancestor here too.
            child: Material(color: Colors.transparent, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
