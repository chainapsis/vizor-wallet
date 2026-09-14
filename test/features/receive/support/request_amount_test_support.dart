import 'package:flutter/material.dart' show Colors, Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_amount_model.dart';
import 'package:zcash_wallet/src/features/receive/widgets/request/request_qr_surface.dart';

const testShieldedAddress =
    'u1tvg2412a23kshieldedaddress000000000000000000000000k64123hhq6d';
const testTransparentAddress = 't1aWwWwqk3jYGkZc7nLGuTvuM8hDywMZCo';
const testMessage = 'Table 4 — two flat whites';

const emptyRequest = ZecRequestView(address: testShieldedAddress);
const requestWithAmount = ZecRequestView(
  address: testShieldedAddress,
  amountZec: '0.5',
  conversionText: r'$35.00',
);
const requestWithMessage = ZecRequestView(
  address: testShieldedAddress,
  amountZec: '0.5',
  conversionText: r'$35.00',
  messageText: testMessage,
);
const transparentRequest = ZecRequestView(
  address: testTransparentAddress,
  amountZec: '0.5',
  conversionText: r'$35.00',
);

/// ZEC typed with no live price to convert it.
const priceUnavailableRequest = ZecRequestView(
  address: testShieldedAddress,
  amountZec: '0.5',
);

const requestWithError = ZecRequestView(
  address: testShieldedAddress,
  amountDisplayText: '0.123456789',
  amountError: kRequestAmountDecimalsError,
);

/// A real software account's UA length (178) with the longest memo ZIP-321
/// allows: 113 modules, the densest code the flow can produce.
final denseRequest = ZecRequestView(
  address: 'u1${'q' * 176}',
  amountZec: '0.5',
  conversionText: r'$35.00',
  messageText: 'm' * 512,
);

/// The field collecting dollars, so its formatters cap at cents.
const usdModeRequest = ZecRequestView(
  address: testShieldedAddress,
  amountInputIsUsd: true,
  conversionText: '0 ZEC',
);

/// Encoding a QR is real async work off the fake-async clock, so these tests
/// must not be able to hang the whole file for the default ten minutes.
const requestEncodeTimeout = Timeout(Duration(seconds: 30));

/// The eight bytes every PNG starts with.
const requestPngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];

const requestDesktopSize = Size(900, 1000);
const requestMobileSize = Size(393, 852);

AppButton requestButton(WidgetTester tester, String key) =>
    tester.widget<AppButton>(find.byKey(ValueKey(key)));

/// The [AppButton] inside a [RequestQrExportButton], which owns the key.
AppButton requestExportButton(WidgetTester tester, String key) =>
    tester.widget<AppButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(AppButton),
      ),
    );

/// Lets an in-flight PNG encode finish: it runs on real time, which the
/// widget tester's fake clock never advances on its own.
Future<void> settleRequestEncode(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

String requestText(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;
Future<void> pumpRequestWidget(
  WidgetTester tester,
  Widget child, {
  Size size = requestDesktopSize,
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
