import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_desktop_ble_probe_dialog.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

import '../../support/ledger_discovery_channel.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;

void main() {
  for (final action in [
    'select',
    'cancel',
    'back',
    'cancel connection',
    'reselect',
    'retry locked',
    'retry disconnected',
    'retry locked after disconnect',
    'retry rejected after disconnect',
  ]) {
    testWidgets('desktop $action drains quiet native discovery', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final native = LedgerDiscoveryChannel();
      final retry = action.startsWith('retry ');
      if (retry) {
        native.currentAppError = PlatformException(
          code: action.substring('retry '.length).split(' ').first,
        );
      }
      final connection = Completer<void>();
      final holdConnection =
          action == 'cancel connection' || action == 'reselect';
      if (holdConnection) {
        native.connecting = connection.future;
      }
      var closed = false;
      var connected = false;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          ledgerMobileBleServiceProvider.overrideWithValue(native.service),
          ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
          if (holdConnection)
            ledgerAppReadinessStateProvider.overrideWith(
              _PreviousReadiness.new,
            ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Stack(
                children: [
                  LedgerDesktopConnectModal(
                    transport: LedgerConnectionTransport.bluetooth,
                    service: native.service,
                    usbConnector: (_) async =>
                        throw StateError('Unexpected USB'),
                    bluetoothConnector: (index, device) async {
                      if (retry) await native.service.currentApp();
                      return LedgerDeviceAccount(
                        ufvk: 'test',
                        seedFingerprint: const [],
                        accountIndex: index,
                        appVersion: '3.9.4',
                        transport: LedgerConnectionTransport.bluetooth,
                        device: device,
                      );
                    },
                    cancelOperation: () async {
                      await native.service.cancelSigning();
                      if (holdConnection && !connection.isCompleted) {
                        connection.complete();
                      }
                    },
                    accountIndex: 0,
                    onConnected: (_) => connected = true,
                    onClose: () => closed = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await pumpLedgerDiscovery(tester);
      await native.devices();
      await pumpLedgerDiscovery(tester);
      if (action == 'cancel' || action == 'back') {
        await tester.tap(
          action == 'back'
              ? find.bySemanticsLabel('Choose connection')
              : find.text('Cancel'),
        );
      } else {
        await tester.tap(
          find.byKey(const ValueKey('ledger_desktop_ble_device_stax')),
        );
      }
      await pumpLedgerDiscovery(tester);
      if (retry) {
        expect(connected, isFalse);
        expect(find.text('Try again'), findsOneWidget);
        if (action.endsWith('after disconnect')) {
          native.dropConnection();
          expect(native.service.connectedDeviceId, 'stax');
        }
        native.currentAppError = null;
        await tester.tap(find.text('Try again'));
        await pumpLedgerDiscovery(tester);
        expect(connected, isTrue);
        expect(native.calls.where((call) => call == 'connect'), hasLength(2));
      }
      if (holdConnection) {
        expect(native.calls.where((call) => call == 'connect'), hasLength(1));
        final procedure = tester.widget<LedgerProcedure>(
          find.byType(LedgerProcedure),
        );
        expect(procedure.currentStep, 0);
        expect(procedure.steps.first.busy, isTrue);
        expect(find.text('Vizor is checking the Zcash app.'), findsNothing);
        await tester.tap(
          action == 'reselect'
              ? find.bySemanticsLabel('Choose another Ledger')
              : find.text('Cancel'),
        );
        await pumpLedgerDiscovery(tester);
      }
      expect(native.eventCalls.take(2), ['listen', 'cancel']);
      if (action == 'select' || retry) {
        expect(connected, isTrue);
      } else if (action == 'reselect') {
        expect(closed, isFalse);
        expect(find.text('Find Ledger'), findsOneWidget);
        expect(native.eventCalls, ['listen', 'cancel', 'listen']);
        await tester.tap(find.text('Cancel'));
        await pumpLedgerDiscovery(tester);
        expect(closed, isTrue);
      } else {
        expect(closed, isTrue);
        expect(connected, isFalse);
      }
      await tester.pumpWidget(const SizedBox());
      await pumpLedgerDiscovery(tester);
      container.dispose();
      await tester.runAsync(native.dispose);
    });
  }

  for (final action in ['cancel', 'cleanup failure']) {
    testWidgets('desktop retry stops after $action during cleanup', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final native = LedgerDiscoveryChannel();
      native.currentAppError = PlatformException(code: 'locked');
      var reads = 0;
      var connected = false;
      var closed = false;
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          ledgerMobileBleServiceProvider.overrideWithValue(native.service),
          ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.light,
              child: Stack(
                children: [
                  LedgerDesktopConnectModal(
                    transport: LedgerConnectionTransport.bluetooth,
                    service: native.service,
                    usbConnector: (_) async =>
                        throw StateError('Unexpected USB'),
                    bluetoothConnector: (index, device) async {
                      reads++;
                      await native.service.currentApp();
                      return LedgerDeviceAccount(
                        ufvk: 'test',
                        seedFingerprint: const [],
                        accountIndex: index,
                        appVersion: '3.9.4',
                        transport: LedgerConnectionTransport.bluetooth,
                        device: device,
                      );
                    },
                    cancelOperation: native.service.cancelSigning,
                    accountIndex: 0,
                    onConnected: (_) => connected = true,
                    onClose: () => closed = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await pumpLedgerDiscovery(tester);
      await native.devices();
      await pumpLedgerDiscovery(tester);
      await tester.tap(
        find.byKey(const ValueKey('ledger_desktop_ble_device_stax')),
      );
      await pumpLedgerDiscovery(tester);
      expect(reads, 1);
      native.currentAppError = null;
      final cleanup = Completer<void>();
      if (action == 'cancel') {
        native.disconnecting = cleanup.future;
      } else {
        native.disconnectError = PlatformException(code: 'busy');
      }
      await tester.tap(find.text('Try again'));
      await pumpLedgerDiscovery(tester);
      expect(reads, 1);
      expect(native.calls.where((c) => c == 'connect'), hasLength(1));
      if (action == 'cancel') {
        await tester.tap(find.text('Cancel'));
        await pumpLedgerDiscovery(tester);
        expect(closed, isFalse);
        cleanup.complete();
        await pumpLedgerDiscovery(tester);
        expect(closed, isTrue);
        expect(connected, isFalse);
        expect(reads, 1);
        expect(native.calls.where((c) => c == 'connect'), hasLength(1));
      } else {
        expect(find.text('Try again'), findsOneWidget);
        native.disconnectError = null;
        await tester.tap(find.text('Try again'));
        await pumpLedgerDiscovery(tester);
        expect(connected, isTrue);
        expect(reads, 2);
        expect(native.calls.where((c) => c == 'connect'), hasLength(2));
      }
      await tester.pumpWidget(const SizedBox());
      await pumpLedgerDiscovery(tester);
      container.dispose();
      await tester.runAsync(native.dispose);
    });
  }

  testWidgets('signing can return from Bluetooth discovery to USB', (
    tester,
  ) async {
    final native = LedgerDiscoveryChannel();
    final container = ProviderContainer(
      overrides: [
        ledgerMobileBleServiceProvider.overrideWithValue(native.service),
        accountProvider.overrideWith(fixture.FakeAccounts.new),
        appSecurityProvider.overrideWith(fixture.FakeSecurity.new),
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
        ledgerRustOperationCancellerProvider.overrideWithValue(() async {}),
      ],
    );
    final request = LedgerDeviceSelectionRequest(
      accountUuid: 'a',
      check: () {},
      canChooseTransport: true,
      prepareDiscovery: () async {},
      verify: (_, _, _) async => false,
      stopDiscovery: native.service.stopDiscovery,
    );
    final cancelled = expectLater(
      request.result,
      throwsA(isA<LedgerMobileException>()),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: Center(
              child: LedgerAccessRecoveryModal(
                account: fixture.account,
                selectionRequest: request,
                onRetry: () {},
                onClose: request.cancel,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Bluetooth'));
    await pumpLedgerDiscovery(tester);
    await native.devices();
    await pumpLedgerDiscovery(tester);
    await tester.tap(find.bySemanticsLabel('Change connection'));
    await pumpLedgerDiscovery(tester);
    expect(find.text('USB'), findsOneWidget);
    expect(find.text('Stopping search'), findsNothing);
    expect(native.eventCalls, ['listen', 'cancel']);
    await tester.pumpWidget(const SizedBox());
    await pumpLedgerDiscovery(tester);
    await cancelled;
    container.dispose();
    await tester.runAsync(native.dispose);
  });
}

class _PreviousReadiness extends LedgerAppReadinessController {
  @override
  LedgerAppReadinessState build() =>
      const LedgerAppReadinessState.ready('3.9.4');
}
