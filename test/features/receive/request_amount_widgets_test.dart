// Lane-agnostic: invoke this untagged file directly with
// --dart-define=VIZOR_FORM_FACTOR=mobile to exercise mobile tokens.
// --tags mobile excludes untagged files.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';
import 'package:zcash_wallet/src/core/widgets/pool_badge.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_card.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';

import 'support/request_amount_test_support.dart';

/// Text the ZIP-321 builder cannot read as a number at all.
const _withFormatError = ZecRequestView(
  address: testShieldedAddress,
  amountDisplayText: '0,5',
  amountError: kRequestAmountFormatError,
);

void main() {
  group('desktop request modal step one', () {
    testWidgets('empty amount shows no QR and a disabled Next', (tester) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(request: emptyRequest),
      );

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
      expect(requestButton(tester, 'request_next_button').onPressed, isNull);
      expect(find.byKey(const ValueKey('request_modal_back')), findsNothing);
    });

    testWidgets('no live price shows the loading pill, not a number', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(
          request: priceUnavailableRequest,
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
      expect(requestButton(tester, 'request_next_button').onPressed, isNotNull);
    });

    testWidgets('an amount enables Create request', (tester) async {
      var advanced = 0;
      await pumpRequestWidget(
        tester,
        RequestAmountCard(request: requestWithAmount, onNext: () => advanced++),
      );

      expect(tester.takeException(), isNull);
      // One label for one commitment, on both form factors.
      expect(find.text('Create request'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(requestButton(tester, 'request_next_button').onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('request_next_button')));
      await tester.pump();
      expect(advanced, 1);
    });

    testWidgets('the message prompt says the link is readable, not encrypted', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(request: emptyRequest),
      );

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
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(request: emptyRequest, messageExpanded: true),
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
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(
          request: requestWithMessage,
          messageExpanded: true,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('request_message_field')),
        findsOneWidget,
      );
      expect(requestText(tester, 'request_message_counter'), endsWith('/512'));
      expect(find.text(kRequestAddMessageLabel), findsNothing);
    });

    testWidgets('a transparent request offers no message at all', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(request: transparentRequest),
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
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(request: requestWithError),
      );

      expect(tester.takeException(), isNull);
      expect(
        requestText(tester, 'request_amount_error_text'),
        kRequestAmountDecimalsError,
      );
      expect(requestButton(tester, 'request_next_button').onPressed, isNull);
      expect(find.byType(RequestSummaryRow), findsNothing);
    });

    testWidgets('an amount the builder cannot read says what to type', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountCard(request: _withFormatError),
      );

      expect(
        requestText(tester, 'request_amount_error_text'),
        kRequestAmountFormatError,
      );
      expect(requestButton(tester, 'request_next_button').onPressed, isNull);
    });

    testWidgets('the amount field normalises a comma to a decimal point', (
      tester,
    ) async {
      final typed = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpRequestWidget(
        tester,
        RequestAmountCard(
          request: emptyRequest,
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
      await pumpRequestWidget(
        tester,
        RequestAmountCard(request: emptyRequest, amountController: controller),
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
      await pumpRequestWidget(
        tester,
        RequestAmountCard(request: emptyRequest, amountController: controller),
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
      await pumpRequestWidget(
        tester,
        RequestAmountCard(
          request: usdModeRequest,
          amountController: controller,
        ),
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
      await pumpRequestWidget(
        tester,
        RequestResultCard(request: requestWithAmount, onBack: () => back++),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(kRequestFlowTitle), findsOneWidget);
      expect(find.byType(RequestQrSurface), findsOneWidget);
      expect(find.text('0.5 ZEC'), findsOneWidget);
      expect(find.text('Shielded'), findsOneWidget);
      expect(find.byType(PoolBadge), findsOneWidget);
      // The link itself is carried by the actions, not printed under the QR.
      expect(find.byKey(const ValueKey('request_uri_line')), findsNothing);
      expect(
        requestButton(tester, 'request_copy_link_button').onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('request_modal_back')));
      await tester.pump();
      expect(back, 1);
    });

    testWidgets('a transparent request states its pool', (tester) async {
      await pumpRequestWidget(
        tester,
        const RequestResultCard(request: transparentRequest),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Transparent'), findsOneWidget);
    });

    testWidgets(
      'saving the QR hands the caller PNG bytes once',
      (tester) async {
        final saved = <Uint8List>[];
        await pumpRequestWidget(
          tester,
          RequestResultCard(
            request: requestWithAmount,
            onSaveQrImage: saved.add,
          ),
        );

        await tester.tap(find.byKey(const ValueKey('request_save_qr_button')));
        await tester.pump();
        // While the encode is in flight the button is inert, so a second tap
        // cannot start a second one.
        expect(
          requestExportButton(tester, 'request_save_qr_button').onPressed,
          isNull,
        );

        await settleRequestEncode(tester);

        expect(saved, hasLength(1));
        expect(saved.single.sublist(0, 8), requestPngSignature);
        expect(
          requestExportButton(tester, 'request_save_qr_button').onPressed,
          isNotNull,
        );
      },
      timeout: requestEncodeTimeout,
    );

    testWidgets('an empty request cannot be saved as an image', (tester) async {
      await pumpRequestWidget(
        tester,
        RequestResultCard(request: emptyRequest, onSaveQrImage: (_) {}),
      );

      expect(
        requestExportButton(tester, 'request_save_qr_button').onPressed,
        isNull,
      );
      expect(
        requestButton(tester, 'request_copy_link_button').onPressed,
        isNull,
      );
    });

    testWidgets('a dense request widens the frame instead of the modules', (
      tester,
    ) async {
      final width = requestModalResultCardWidth(denseRequest.qrData);
      expect(width, greaterThan(kRequestModalResultCardWidth));

      await pumpRequestWidget(
        tester,
        Center(
          child: AppModalCard(
            width: width,
            child: RequestResultCard(request: denseRequest),
          ),
        ),
      );

      // A 288 frame squeezes this symbol under the two-pixel module floor,
      // which is an assertion in debug and a hard-to-scan code in release.
      expect(tester.takeException(), isNull);
      final qr = tester.getRect(
        find.byKey(const ValueKey('request_qr_surface')),
      );
      expect(
        qr.width - AppSpacing.sm * 2,
        greaterThanOrEqualTo(requestQrSideFor(denseRequest.qrData) - 0.01),
      );
    });

    testWidgets('an ordinary request keeps the fixed frame', (tester) async {
      expect(
        requestModalResultCardWidth(requestWithAmount.qrData),
        kRequestModalResultCardWidth,
      );
      expect(
        requestModalResultCardWidth(emptyRequest.qrData),
        kRequestModalResultCardWidth,
      );
      // A pane too narrow for the code it holds caps rather than overflows.
      expect(
        requestModalResultCardWidth(denseRequest.qrData, maxWidth: 300),
        300,
      );
    });

    testWidgets('a failed save encode is reported, not swallowed', (
      tester,
    ) async {
      var reported = 0;
      await pumpRequestWidget(
        tester,
        RequestResultCard(
          request: requestWithAmount,
          onSaveQrImage: (_) {},
          onSaveQrImageError: () => reported++,
        ),
      );

      final export = tester.widget<RequestQrExportButton>(
        find.byKey(const ValueKey('request_save_qr_button')),
      );
      expect(export.onError, isNotNull);
      export.onError!();
      expect(reported, 1);
    });
  });
}
