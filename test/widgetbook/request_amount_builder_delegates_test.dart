import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_card.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_sheet.dart';
import 'package:zcash_wallet/widgetbook/request_amount_use_cases.dart';
import 'package:zcash_wallet/widgetbook/receive_use_cases.dart';

import '../figma_compare/figma_compare_font_loader.dart';
import 'support/wb_gallery_harness.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  final cases =
      <(WidgetBuilder, ReceiveRequestFixture, RequestModalStep, bool)>[
        (
          buildRequestModalStepOneEmptyUseCase,
          ReceiveRequestFixture.empty,
          RequestModalStep.compose,
          false,
        ),
        (
          buildRequestModalStepOneAmountUseCase,
          ReceiveRequestFixture.amount,
          RequestModalStep.compose,
          false,
        ),
        (
          buildRequestModalStepOneTransparentUseCase,
          ReceiveRequestFixture.transparentAddress,
          RequestModalStep.compose,
          false,
        ),
        (
          buildRequestModalStepOneAmountErrorUseCase,
          ReceiveRequestFixture.amountError,
          RequestModalStep.compose,
          false,
        ),
        (
          buildRequestModalStepTwoTransparentUseCase,
          ReceiveRequestFixture.transparentAddress,
          RequestModalStep.result,
          false,
        ),
        (
          buildRequestMobileComposeEmptyUseCase,
          ReceiveRequestFixture.empty,
          RequestModalStep.compose,
          true,
        ),
        (
          buildRequestMobileComposeUsdUseCase,
          ReceiveRequestFixture.amountInUsd,
          RequestModalStep.compose,
          true,
        ),
        (
          buildRequestMobileResultTransparentUseCase,
          ReceiveRequestFixture.transparentAddress,
          RequestModalStep.result,
          true,
        ),
      ];
  for (final (builder, fixture, step, mobile) in cases) {
    testWidgets('request delegate preserves $fixture $step mobile=$mobile', (
      tester,
    ) async {
      await pumpUseCase(tester, builder);
      final ZecRequestView request;
      if (!mobile) {
        final surface = tester.widget<RequestAmountSurface>(
          find.byType(RequestAmountSurface),
        );
        expect(surface.step, step);
        request = surface.request;
      } else if (step == RequestModalStep.compose) {
        request = tester
            .widget<RequestAmountSheetCompose>(
              find.byType(RequestAmountSheetCompose),
            )
            .request;
      } else {
        request = tester
            .widget<RequestAmountSheetResult>(
              find.byType(RequestAmountSheetResult),
            )
            .request;
      }
      expect(request, same(receiveRequestView(fixture)));
      expect(tester.takeException(), isNull);
      await disposeTree(tester);
    });
  }
  testWidgets('mobile entry delegates to the existing Receive screen', (
    tester,
  ) async {
    await pumpUseCase(tester, (context) {
      expect(
        buildRequestMobileEntryUseCase(context).runtimeType,
        buildReceiveMobileShieldedUseCase(context).runtimeType,
      );
      return buildRequestMobileEntryUseCase(context);
    });
    expect(
        find.byKey(const ValueKey('mobile_receive_request')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });
}
