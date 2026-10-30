import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_bluetooth_recovery.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_desktop_ble_probe_dialog.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

import '../../support/ledger_access_fake.dart';

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _harness(Widget child, LedgerAccessFake service) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ledgerMobileBleServiceProvider.overrideWithValue(service),
    ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
  ],
  child: MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: Stack(children: [child]),
    ),
  ),
);

LedgerDesktopConnectModal _modal(
  LedgerAccessFake service, {
  bool bluetooth = true,
  LedgerAccountConnector? usb,
  VoidCallback? onClose,
}) => LedgerDesktopConnectModal(
  transport: bluetooth
      ? LedgerConnectionTransport.bluetooth
      : LedgerConnectionTransport.usb,
  service: service,
  usbConnector: usb ?? (_) async => throw StateError('Unexpected USB'),
  bluetoothConnector: (_, _) async => throw StateError('Unexpected Bluetooth'),
  cancelOperation: () async {},
  accountIndex: 0,
  onConnected: (_) => fail('Unexpected successful account import'),
  onClose: onClose ?? () {},
);

void main() {
  testWidgets('access preparation never claims discovery has started', (
    tester,
  ) async {
    final service = LedgerAccessFake()
      ..pendingStatus = Completer<LedgerBluetoothAccessStatus>();
    await tester.pumpWidget(_harness(_modal(service), service));
    await _frames(tester);
    expect(find.text('Checking Bluetooth access…'), findsOneWidget);
    expect(find.textContaining('macOS may ask'), findsOneWidget);
    expect(find.text('Searching for nearby Ledgers…'), findsNothing);
    expect(service.discoveries, 0);
    service.pendingStatus!.complete(service.status);
    await _frames(tester);
    expect(find.text('Access is restricted'), findsOneWidget);
  });

  testWidgets('restricted onboarding closes only after successful cleanup', (
    tester,
  ) async {
    final service = LedgerAccessFake();
    var closes = 0;
    await tester.pumpWidget(
      _harness(_modal(service, onClose: () => closes++), service),
    );
    await _frames(tester);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Close'))
          .onPressed,
      isNotNull,
    );
    service.disconnectError = StateError('cleanup failed');
    await tester.tap(find.text('Close'));
    await _frames(tester);
    expect(closes, 0);
    expect(find.text('Could not finish cleanup. Try again.'), findsOneWidget);
    expect(service.discoveries, 0);
    service.disconnectError = null;
    await tester.tap(find.text('Try again'));
    await _frames(tester);
    expect(closes, 1);
    expect(service.discoveries, 0);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets('restricted settings launch (fails: $fails) retains exit', (
      tester,
    ) async {
      final service = LedgerAccessFake()
        ..opensSettings = !fails
        ..pendingSettings = Completer<bool>();
      var closes = 0;
      await tester.pumpWidget(
        _harness(
          Center(
            child: SizedBox(
              width: 400,
              child: LedgerBluetoothRecovery(
                service: service,
                onClose: () => closes++,
              ),
            ),
          ),
          service,
        ),
      );
      await _frames(tester);
      final settingsAction = tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Open settings'))
          .onPressed!;
      final closeAction = tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Close'))
          .onPressed!;
      settingsAction();
      settingsAction();
      closeAction(); // A callback from the previous frame must also be blocked.
      await _frames(tester);
      expect(service.settings, 1);
      expect(closes, 0);
      service.pendingSettings!.complete(!fails);
      await _frames(tester);
      expect(find.text('Close'), findsOneWidget);
      expect(find.textContaining('restricted by your device'), findsOneWidget);
      if (fails) {
        expect(
          find.textContaining('manually to review access'),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Close'));
      expect(closes, 1);
      expect(service.requests, 0);
      expect(service.discoveries, 0);
    });
  }

  testWidgets('settings callbacks captured before cancellation stay inert', (
    tester,
  ) async {
    final service = LedgerAccessFake();
    await tester.pumpWidget(
      _harness(
        LedgerBluetoothRecovery(service: service, onClose: () {}),
        service,
      ),
    );
    await _frames(tester);
    final settingsAction = tester
        .widget<AppButton>(find.widgetWithText(AppButton, 'Open settings'))
        .onPressed!;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LedgerBluetoothRecovery)),
    );
    container.read(ledgerDeviceRequestsProvider).cancel();
    settingsAction();
    expect(service.settings, 0);
    expect(service.requests, 0);
  });

  for (final (name, error, expected, retryable) in [
    (
      'unknown',
      StateError('unexpected export failure'),
      'Reconnect Ledger with a USB cable, unlock it with your PIN, and open the Zcash app.',
      true,
    ),
    (
      'USB permissions',
      StateError('ledger_transport: open Ledger HID device: permission denied'),
      'Check USB device permissions',
      true,
    ),
    (
      'USB interrupted',
      StateError('ledger_transport: read failed'),
      'USB connection to your Ledger was interrupted',
      true,
    ),
    (
      'wrong app',
      StateError('ledger_status_6e00: wrong app'),
      'Open the Zcash app on your Ledger.',
      true,
    ),
    (
      'rejected request',
      StateError('ledger_status_6a80: invalid key path'),
      'Check the account number.',
      false,
    ),
    (
      'declined',
      StateError('ledger_status_6985: declined'),
      'Sharing was declined on Ledger.',
      true,
    ),
  ]) {
    testWidgets('USB $name preserves the appropriate recovery action', (
      tester,
    ) async {
      final service = LedgerAccessFake();
      var exports = 0;
      var closes = 0;
      await tester.pumpWidget(
        _harness(
          _modal(
            service,
            bluetooth: false,
            usb: (_) async {
              exports++;
              throw error;
            },
            onClose: () => closes++,
          ),
          service,
        ),
      );
      await _frames(tester);
      expect(find.textContaining(expected), findsOneWidget);
      if (name == 'USB interrupted') {
        expect(find.textContaining('Open the Zcash app'), findsOneWidget);
      }
      expect(find.text('Try again'), retryable ? findsOneWidget : findsNothing);
      if (!retryable) {
        await tester.tap(find.text('Back'));
        await _frames(tester);
        expect(closes, 1);
        expect(exports, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
