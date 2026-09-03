@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';

void main() {
  testWidgets('collapsed address and pool badge fit at 2x text scale', (
    tester,
  ) async {
    // Keep the narrow width that exercises the horizontal overflow without
    // changing the card's pinned-amount contract for unusually short screens.
    const size = Size(320, 852);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AppTheme(
          data: AppThemeData.light,
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: PaymentRequestSurface(
                layout: PaymentRequestLayout.mobile,
                request: const PaymentRequestView(
                  source: PaymentRequestSource.link,
                  requesterLabel: 'Blue Door Coffee',
                  amountZecText: '0.5 ZEC',
                  address:
                      'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
                      '73d57f73c6dc05121591a83861cd190591',
                ),
                onContinue: () {},
                onEdit: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.text('u195091 ... 190591')).overflow,
      TextOverflow.ellipsis,
    );
  });
}
