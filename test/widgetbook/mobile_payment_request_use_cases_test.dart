@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_card.dart';
import 'package:zcash_wallet/src/features/send/widgets/payment_request_surface.dart';
import 'package:zcash_wallet/widgetbook/payment_request_use_cases.dart';

void main() {
  testWidgets('mobile status previews show details and matching actions', (
    tester,
  ) async {
    for (final (builder, label, showsStatus) in <(WidgetBuilder, String, bool)>[
      (buildMobilePaymentRequestCheckingUseCase, 'Checking…', false),
      (buildMobilePaymentRequestInvalidAddressUseCase, 'Review payment', true),
      (buildMobilePaymentRequestInsufficientUseCase, 'Review payment', true),
      (buildMobilePaymentRequestSyncingUseCase, 'Review payment', true),
      (buildMobilePaymentRequestFailedUseCase, 'Check again', true),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPaymentRequest(
        tester,
        size: const Size(393, 852),
        child: Builder(builder: builder),
      );
      expect(
        find.byKey(const ValueKey('external_request_warning')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment_request_continue')),
        findsOneWidget,
      );
      expect(find.text(label), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_request_status')),
        showsStatus ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('collapsed address and pool badge fit at 2x text scale', (
    tester,
  ) async {
    // Keep the narrow width that exercises the horizontal overflow without
    // changing the card's pinned-amount contract for unusually short screens.
    const size = Size(320, 852);
    await _pumpPaymentRequest(
      tester,
      size: size,
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.text('u195091 ... 190591')).overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('disclosure heights follow nonlinear text scaling', (
    tester,
  ) async {
    const scaler = _NonlinearTestScaler();
    await _pumpPaymentRequest(
      tester,
      size: const Size(393, 852),
      textScaler: scaler,
    );

    for (final key in <String>[
      'payment_request_requester_toggle',
      'payment_request_memo_toggle',
    ]) {
      final button = tester.widget<AppButton>(find.byKey(ValueKey(key)));
      expect(button.growWithContent, isTrue);
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('external introductions keep scan and review choices visible', (
    tester,
  ) async {
    for (final (builder, size) in <(WidgetBuilder, Size)>[
      (buildMobilePaymentRequestFullUseCase, const Size(393, 852)),
      (buildMobilePaymentRequestFullUseCase, const Size(375, 812)),
      (buildMobilePaymentRequestMinimalUseCase, const Size(393, 852)),
      (buildMobilePaymentRequestMinimalUseCase, const Size(375, 812)),
    ]) {
      await _pumpPaymentRequest(
        tester,
        size: size,
        child: Builder(builder: builder),
      );

      expect(tester.takeException(), isNull, reason: '$builder at $size');
      final action = tester.getRect(
        find.byKey(const ValueKey('payment_request_scan')),
      );
      expect(action.top, greaterThan(0));
      expect(action.bottom, lessThan(size.height));
      expect(find.text('0.5 ZEC'), findsNothing);
      expect(find.text('u195091 ... 190591'), findsNothing);
      expect(find.text('Scan original QR'), findsOneWidget);
      expect(find.text('Review link details'), findsOneWidget);
    }
  });
}

Future<void> _pumpPaymentRequest(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  Widget? child,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child:
                child ??
                PaymentRequestSurface(
                  layout: PaymentRequestLayout.mobile,
                  request: const PaymentRequestView(
                    source: PaymentRequestSource.qrCode,
                    requesterLabel: 'Blue Door Coffee',
                    note: 'Meet at the side entrance.',
                    amountZecText: '0.5 ZEC',
                    address:
                        'u1950915183f0fed838d6d2dd92d6f4111ed3c6dd4e3eb19a3702b'
                        '73d57f73c6dc05121591a83861cd190591',
                    memo: 'Table 4',
                  ),
                  onScan: () {},
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
}

final class _NonlinearTestScaler extends TextScaler {
  const _NonlinearTestScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 16 ? fontSize * 2 : fontSize * 1.5;

  @override
  double get textScaleFactor => 2;
}
