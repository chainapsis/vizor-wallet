@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_sheet.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_scan_sheet.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

import '../../support/payment_links_screen_support.dart';

void main() {
  setUpAll(loadPaymentLinksTestFonts);

  testWidgets(
    'address and payment QR stay in the scanner; a card completes once',
    (tester) async {
      final accepted = <VizorPaymentLink>[];
      await _pumpScanner(tester, onScanned: accepted.add);

      for (final raw in ['u1address', 'zcash:u1address?amount=1']) {
        _scan(tester, raw);
        await tester.pump();
        expect(find.text("This isn't a gift card QR code."), findsOneWidget);
        expect(accepted, isEmpty);
      }

      _scan(tester, incomingLink.toUri().toString());
      _scan(tester, incomingLink.toUri().toString());
      expect(accepted.single.address, incomingLink.address);
    },
  );

  testWidgets('a card for a different wallet network stays in the scanner', (
    tester,
  ) async {
    final accepted = <VizorPaymentLink>[];
    await _pumpScanner(tester, networkName: 'regtest', onScanned: accepted.add);
    _scan(tester, incomingLink.toUri().toString());
    await tester.pump();
    expect(
      find.text('This gift card is for a different network.'),
      findsOneWidget,
    );
    expect(accepted, isEmpty);
  });

  testWidgets('closing ignores later camera detections', (tester) async {
    final accepted = <VizorPaymentLink>[];
    var closeCalls = 0;
    await _pumpScanner(
      tester,
      onScanned: accepted.add,
      onClose: () => closeCalls++,
    );
    await tester.tap(find.bySemanticsLabel('Close scanner'));
    _scan(tester, incomingLink.toUri().toString());
    expect(closeCalls, 1);
    expect(accepted, isEmpty);
  });
}

void _scan(WidgetTester tester, String raw) {
  tester
      .widget<PlainQrScannerView>(
        find.byType(PlainQrScannerView, skipOffstage: false),
      )
      .onComplete(raw);
}

Future<void> _pumpScanner(
  WidgetTester tester, {
  String networkName = 'main',
  ValueChanged<VizorPaymentLink>? onScanned,
  VoidCallback? onClose,
  MobileScannerController? controller,
}) async {
  await tester.binding.setSurfaceSize(const Size(375, 667));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final scanner = controller ?? MobileScannerController(autoStart: false);
  if (controller == null) addTearDown(scanner.dispose);
  scanner.value = scanner.value.copyWith(isInitialized: true, isRunning: true);
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MobileModalCard(
            child: PaymentLinkScanSheet(
              controller: scanner,
              networkName: networkName,
              onScanned: onScanned ?? (_) {},
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
