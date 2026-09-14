// Lane-agnostic: invoke this untagged file directly with
// --dart-define=VIZOR_FORM_FACTOR=mobile to exercise mobile tokens.
// --tags mobile excludes untagged files.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_sheet.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';

import 'support/request_amount_test_support.dart';

void main() {
  group('mobile request sheet', () {
    testWidgets('no live price shows the loading pill, not a number', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(
          request: priceUnavailableRequest,
          onToggleAmountUnit: null,
        ),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(request: emptyRequest),
        size: requestMobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(kRequestFlowTitle), findsOneWidget);
      expect(find.text('Create request'), findsOneWidget);
      expect(requestButton(tester, 'request_create_button').onPressed, isNull);
      // No Max: a request is not a spend.
      expect(find.text('Max'), findsNothing);
    });

    testWidgets('step one shows the message it will attach', (tester) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(request: requestWithMessage),
        size: requestMobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(
        requestButton(tester, 'request_create_button').onPressed,
        isNotNull,
      );
      expect(requestText(tester, 'request_message_preview'), testMessage);
    });

    testWidgets('step one hides the message row for a transparent address', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(request: transparentRequest),
        size: requestMobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('request_message_row')), findsNothing);
    });

    testWidgets('an invalid amount states the correction to make', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(request: requestWithError),
        size: requestMobileSize,
      );

      expect(tester.takeException(), isNull);
      // Red digits alone say something is wrong without saying what, and the
      // two causes need opposite fixes.
      expect(
        requestText(tester, 'request_amount_error_text'),
        kRequestAmountDecimalsError,
      );
      expect(requestButton(tester, 'request_create_button').onPressed, isNull);
    });

    testWidgets('a valid amount shows no error row', (tester) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(request: requestWithAmount),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        RequestAmountSheetCompose(
          request: emptyRequest,
          amountController: controller,
          onAmountChanged: typed.add,
        ),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        RequestAmountSheetCompose(
          request: emptyRequest,
          amountController: controller,
        ),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        RequestAmountSheetCompose(
          request: usdModeRequest,
          amountController: controller,
        ),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetCompose(
          request: priceUnavailableRequest,
          onToggleAmountUnit: null,
        ),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        RequestAmountSheetCompose(
          request: requestWithAmount,
          onToggleAmountUnit: () {},
        ),
        size: requestMobileSize,
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
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetResult(request: requestWithMessage),
        size: requestMobileSize,
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

    testWidgets('sharing hands over the QR PNG', (tester) async {
      Uint8List? sharedPng;
      await pumpRequestWidget(
        tester,
        RequestAmountSheetResult(
          request: requestWithMessage,
          onShareRequest: (png) {
            sharedPng = png;
          },
        ),
        size: requestMobileSize,
      );

      await tester.tap(find.byKey(const ValueKey('request_share_button')));
      await tester.pump();
      await settleRequestEncode(tester);

      expect(sharedPng, isNotNull);
      expect(sharedPng!.sublist(0, 8), requestPngSignature);
    }, timeout: requestEncodeTimeout);

    testWidgets('the sheet draws the densest request without squeezing it', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        RequestAmountSheetResult(request: denseRequest),
        size: requestMobileSize,
      );

      expect(tester.takeException(), isNull);
      final qr = tester.getRect(
        find.byKey(const ValueKey('request_qr_surface')),
      );
      expect(
        qr.width - AppSpacing.sm * 2,
        greaterThanOrEqualTo(requestQrSideFor(denseRequest.qrData) - 0.01),
      );
    });

    testWidgets('a failed share encode is reported, not swallowed', (
      tester,
    ) async {
      var reported = 0;
      await pumpRequestWidget(
        tester,
        RequestAmountSheetResult(
          request: requestWithMessage,
          onShareRequest: (_) {},
          onShareError: () => reported++,
        ),
        size: requestMobileSize,
      );

      final export = tester.widget<RequestQrExportButton>(
        find.byKey(const ValueKey('request_share_button')),
      );
      expect(export.onError, isNotNull);
      export.onError!();
      expect(reported, 1);
    });

    testWidgets('step two reports a transparent request as transparent', (
      tester,
    ) async {
      await pumpRequestWidget(
        tester,
        const RequestAmountSheetResult(request: transparentRequest),
        size: requestMobileSize,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Transparent'), findsOneWidget);
    });
  });
}

TextStyle _textStyle(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).style!;
