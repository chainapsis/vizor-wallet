@Tags(['mobile'])
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_sheet.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/send_gallery.dart';
import 'package:zcash_wallet/widgetbook/send_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import 'support/wb_gallery_harness.dart';

void main() {
  testWidgets('Send screen continues from compose to a simulated receipt', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildSendScreenGalleryCase,
      knobs: {'Layout': wbLayoutLabel(WbLayout.mobile)},
      canvasSize: const Size(520, 932),
    );
    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_address_input')),
      kSendScreenFixtureAddress,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_continue')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_send_amount_field')),
      '0.5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_review_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_send_confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(MobileSendStatusScreen), findsOneWidget);
    expect(
      find.byKey(const ValueKey('send_simulated_result_notice')),
      findsOneWidget,
    );
  });

  testWidgets('Receive screen returns from request result to its draft', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      buildReceiveScreenGalleryCase,
      knobs: {
        'Layout': wbLayoutLabel(WbLayout.mobile),
        'Address': receiveMobileAddressCaseLabel(
          ReceiveMobileAddressCase.loaded,
        ),
      },
      canvasSize: const Size(520, 932),
    );
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.byKey(const ValueKey('mobile_receive_request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('request_amount_input')),
      '0.5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('request_create_button')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('request_copy_link_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('request_sheet_back')));
    await tester.pumpAndSettle();
    expect(find.byType(RequestAmountSheetCompose), findsOneWidget);
  });
}
