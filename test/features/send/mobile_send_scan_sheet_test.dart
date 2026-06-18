@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_card.dart';
import 'package:zcash_wallet/src/features/address_scan/widgets/mobile_address_scan_view.dart'
    show MobileScanOutcome;
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_scan_screen.dart';

void main() {
  testWidgets('scan sheet overlays the current page instead of replacing it', (
    tester,
  ) async {
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) => Scaffold(
              body: Stack(
                children: [
                  const Center(child: Text('Send page behind scanner')),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        unawaited(
                          showMobileSendScanSheet(
                            context,
                            controller: controller,
                            resolve: (raw) async =>
                                MobileScanOutcome.accepted(raw),
                          ),
                        );
                      },
                      child: const Text('Open scanner'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();

    expect(find.text('Send page behind scanner'), findsOneWidget);
    expect(find.byType(MobileAddressScanCard), findsOneWidget);
    expect(find.text('Scan the address QR code'), findsOneWidget);
  });
}
