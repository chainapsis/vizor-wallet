@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_bluetooth_content.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';

import '../../support/ledger_access_fake.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final (platform, location) in [
    (TargetPlatform.iOS, false),
    (TargetPlatform.android, false),
    (TargetPlatform.android, true),
  ]) {
    for (final small in [false, true]) {
      testWidgets(
        '$platform restricted access location=$location small=$small',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = small
              ? const Size(320, 568)
              : const Size(393, 852);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = LedgerAccessFake()
            ..status = LedgerBluetoothAccessStatus(
              LedgerBluetoothPermission.restricted,
              locationPermission: location,
            )
            ..opensSettings = false;
          var retries = 0;
          var closes = 0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
                ledgerMobileBleServiceProvider.overrideWithValue(service),
                ledgerTargetPlatformProvider.overrideWithValue(platform),
              ],
              child: MaterialApp(
                home: AppTheme(
                  data: small ? AppThemeData.dark : AppThemeData.light,
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(small ? 1.8 : 1),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const Scaffold(body: Text('Review send')),
                          MobileLedgerSigningSurface(
                            canLeave: true,
                            onBack: () => closes++,
                            child: MobileLedgerBluetoothContent(
                              service: service,
                              onRetry: () => retries++,
                              onClose: () => closes++,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _frames(tester);
          expect(find.text('Access is restricted'), findsOneWidget);
          expect(find.text('Allow access'), findsNothing);
          expect(
            find.textContaining(
              location
                  ? 'Check location access'
                  : platform == TargetPlatform.iOS
                  ? 'Check Vizor’s Bluetooth access'
                  : 'Check Nearby devices access',
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Open settings'));
          await tester.tap(find.text('Open settings'));
          await _frames(tester);
          expect(service.settings, 1);
          expect(
            find.textContaining('manually to review access'),
            findsOneWidget,
          );
          expect(find.text('Close'), findsOneWidget);
          expect(retries, 0);
          expect(tester.takeException(), isNull);

          service.status = const LedgerBluetoothAccessStatus(
            LedgerBluetoothPermission.granted,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await _frames(tester);
          expect(find.text('Reconnect Ledger'), findsOneWidget);
          expect(find.text('Open settings'), findsNothing);
          expect(retries, 0);
          expect(service.requests, 0);
          expect(service.discoveries, 0);
          await tester.tap(find.text('Reconnect'));
          expect(retries, 1);
          expect(closes, 0);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }
}
