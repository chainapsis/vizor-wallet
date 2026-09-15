@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/features/receive/screens/mobile/mobile_receive_screen.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_sheet.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_status_screen.dart';
import 'package:zcash_wallet/widgetbook/gallery/receive_gallery.dart';
import 'package:zcash_wallet/widgetbook/gallery/send_gallery.dart';
import 'package:zcash_wallet/widgetbook/receive_use_cases.dart';
import 'package:zcash_wallet/widgetbook/send_screen_use_cases.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import 'support/wb_gallery_harness.dart';

void main() {
  final clipboardWrites = <Object?>[];
  setUp(() {
    clipboardWrites.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call.arguments);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('Receive snapshot copy stays inside the fixture', (tester) async {
    await pumpUseCase(tester, buildReceiveMobileShieldedUseCase);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_receive_copy')));
    await tester.pumpAndSettle();
    expect(find.text('Address copied'), findsOneWidget);
    expect(clipboardWrites, isEmpty);
  });

  testWidgets('Standalone request sheet copy stays inside the fixture', (
    tester,
  ) async {
    await pumpUseCase(tester, buildReceiveRequestSheetGalleryCase);
    await tester.enterText(
      find.byKey(const ValueKey('request_amount_input')),
      '0.5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('request_create_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('request_copy_link_button')));
    await tester.pumpAndSettle();
    expect(find.text(kRequestLinkCopiedToast), findsOneWidget);
    expect(clipboardWrites, isEmpty);
  });

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
    final screen = find.byType(MobileReceiveScreen);
    final nav = find.descendant(
      of: screen,
      matching: find.byType(MobileTopNav),
    );
    expect(
      tester.getTopLeft(nav).dy - tester.getTopLeft(screen).dy,
      kWbPhoneStatusBarInset,
    );
    final media = MediaQuery.of(tester.element(screen));
    expect(media.size, kWbPhoneSize);
    expect(media.padding, const EdgeInsets.only(top: kWbPhoneStatusBarInset));
    expect(media.viewPadding, media.padding);
    expect(media.viewInsets, EdgeInsets.zero);
    await tester.tap(find.byKey(const ValueKey('mobile_receive_copy')));
    await tester.pumpAndSettle();
    expect(find.text('Address copied'), findsOneWidget);
    expect(clipboardWrites, isEmpty);
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
    await tester.tap(find.byKey(const ValueKey('request_copy_link_button')));
    await tester.pumpAndSettle();
    expect(find.text(kRequestLinkCopiedToast), findsOneWidget);
    expect(clipboardWrites, isEmpty);
    await tester.tap(find.byKey(const ValueKey('request_sheet_back')));
    await tester.pumpAndSettle();
    expect(find.byType(RequestAmountSheetCompose), findsOneWidget);
  });
}
