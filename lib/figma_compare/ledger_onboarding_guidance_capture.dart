import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/features/ledger/ledger_capability.dart';
import '../src/features/ledger/services/ledger_account_service.dart';
import '../src/features/ledger/services/ledger_app_readiness_service.dart';
import '../src/features/ledger/services/ledger_bluetooth_access.dart';
import '../src/features/ledger/services/ledger_mobile_ble_service.dart';
import '../src/features/onboarding/ledger/ledger_desktop_ble_probe_dialog.dart';
import '../src/providers/account_models.dart';

Widget buildLedgerOnboardingAccessPreparation(BuildContext context) =>
    _onboarding(preparing: true);

Widget buildLedgerOnboardingAccessRestricted(BuildContext context) =>
    _onboarding();

Widget buildLedgerOnboardingUsbError(BuildContext context) =>
    _onboarding(usb: true);

Widget _onboarding({bool preparing = false, bool usb = false}) {
  final service = _GuidanceCaptureBle(preparing: preparing);
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ledgerMobileBleServiceProvider.overrideWithValue(service),
    ],
    child: Stack(
      fit: StackFit.expand,
      children: [
        LedgerDesktopConnectModal(
          transport: usb
              ? LedgerConnectionTransport.usb
              : LedgerConnectionTransport.bluetooth,
          service: service,
          usbConnector: (_) async =>
              throw StateError('Scripted export failure'),
          bluetoothConnector: (_, _) async =>
              throw StateError('Capture never exports keys'),
          cancelOperation: () async {},
          accountIndex: 0,
          onConnected: (_) {},
          onClose: () {},
        ),
      ],
    ),
  );
}

class _GuidanceCaptureBle
    implements LedgerMobileBleService, LedgerBluetoothAccess {
  _GuidanceCaptureBle({required this.preparing});
  final bool preparing;
  final _pending = Completer<LedgerBluetoothAccessStatus>();

  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async => preparing
      ? _pending.future
      : const LedgerBluetoothAccessStatus(
          LedgerBluetoothPermission.restricted,
          macOS: true,
        );
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<bool> openBluetoothSettings() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Capture never performs native Ledger work');
}

/// The viewing-key step names the account as Zcash 3.10.0 shows it.
Widget buildLedgerOnboardingViewingKeyApproval(BuildContext context) {
  final service = _GuidanceCaptureBle(preparing: false);
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ledgerMobileBleServiceProvider.overrideWithValue(service),
      ledgerAppReadinessStateProvider.overrideWith(_ReadyReadiness.new),
    ],
    child: Stack(
      fit: StackFit.expand,
      children: [
        LedgerDesktopConnectModal(
          transport: LedgerConnectionTransport.usb,
          service: service,
          usbConnector: (_) => Completer<LedgerDeviceAccount>().future,
          bluetoothConnector: (_, _) => Completer<LedgerDeviceAccount>().future,
          cancelOperation: () async {},
          accountIndex: 3,
          onConnected: (_) {},
          onClose: () {},
        ),
      ],
    ),
  );
}

class _ReadyReadiness extends LedgerAppReadinessController {
  @override
  LedgerAppReadinessState build() =>
      const LedgerAppReadinessState.ready('3.10.0');
}
