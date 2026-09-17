// ignore_for_file: depend_on_referenced_packages
// Deterministic product widgets with scripted BLE failures; no native device IO.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/ledger/services/ledger_bluetooth_access.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/ledger/services/ledger_failure_guidance.dart';
import '../src/features/ledger/services/ledger_mobile_ble_service.dart';
import '../src/features/ledger/widgets/ledger_signing_modal.dart';
import '../src/features/onboarding/mobile/mobile_ledger_device_sheet.dart';
import '../src/rust/api/ledger.dart' as rust_ledger;
import '../widgetbook/ledger_use_cases.dart';

Widget _signing(
  LedgerMobileFailure failure, {
  LedgerBluetoothPermission permission = LedgerBluetoothPermission.settings,
  bool locationPermission = false,
}) {
  final guidance = ledgerFailureGuidance(
    LedgerMobileException(failure, 'Scripted capture failure'),
  )!;
  return Builder(
    builder: (context) => ColoredBox(
      color: context.colors.background.window,
      child: buildLedgerSigningPreview(
        phase: LedgerSigningModalPhase.failed,
        bluetoothService: _PermissionCaptureBle(
          failure,
          permission,
          locationPermission: locationPermission,
        ),
        mobileTitle: 'Confirm transaction',
        mobile: kAppFormFactor == AppFormFactor.mobile,
        failureOverride: LedgerSigningFailurePresentation(
          title: 'Ledger needs attention',
          statusLabel: 'Action needed',
          message: guidance.message,
          showDeviceAppPrompt: guidance.showDeviceAppPrompt,
          bluetoothRecovery: guidance.bluetoothRecovery,
          actionLabel: 'Try again',
        ),
      ),
    ),
  );
}

Widget buildLedgerPermissionCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.permissionDenied);
Widget buildLedgerPairingCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.pairingInvalid);
Widget buildLedgerBluetoothOffCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.bluetoothOff);
Widget buildLedgerDisconnectedCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.disconnected);
Widget buildLedgerBusyCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.busy);
Widget buildLedgerLocationCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.locationDisabled);

Widget _picker(LedgerMobileFailure failure) => Builder(
  builder: (context) => MobileModalOverlay(
    background: ColoredBox(color: context.colors.background.window),
    child: MobileLedgerDeviceSheet(
      service: _CaptureBle(failure, retainDevices: true),
      onSelected: (_) {},
      onClose: () {},
    ),
  ),
);

Widget buildLedgerPickerPairingCapture(BuildContext context) =>
    _picker(LedgerMobileFailure.pairingInvalid);
Widget buildLedgerPickerLocationCapture(BuildContext context) =>
    _picker(LedgerMobileFailure.locationDisabled);

class _CaptureBle implements LedgerMobileBleService {
  _CaptureBle(this.failure, {this.retainDevices = false});

  final LedgerMobileFailure failure;
  final bool retainDevices;

  @override
  String? get connectedDeviceId => null;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> cancelSigning() async {}
  @override
  Future<void> connect(LedgerBleDevice device) async =>
      throw LedgerMobileException(failure, 'Scripted capture failure');
  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => Stream.fromIterable([
    if (retainDevices)
      const LedgerDevicesDiscovered([
        LedgerBleDevice(
          id: 'capture-flex',
          name: 'Ledger Flex',
          model: 'Ledger Flex',
        ),
      ]),
    LedgerDiscoveryFailed(
      LedgerMobileException(failure, 'Scripted capture failure'),
    ),
  ]);
  @override
  Future<LedgerMobileAppInfo> currentApp() =>
      throw StateError('Capture never queries a device');
  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() => currentApp();
  @override
  Future<List<Uint8List>> exchangeApdus(
    List<rust_ledger.LedgerApduCommand> commands,
  ) => throw StateError('Capture never signs');
  @override
  Future<List<Uint8List>> exchangeUfvk(rust_ledger.LedgerUfvkApduPlan plan) =>
      throw StateError('Capture never exports keys');
}

Widget buildLedgerPermissionRequestCapture(BuildContext context) => _signing(
  LedgerMobileFailure.permissionDenied,
  permission: LedgerBluetoothPermission.requestable,
);
Widget buildLedgerPermissionRestrictedCapture(BuildContext context) => _signing(
  LedgerMobileFailure.permissionDenied,
  permission: LedgerBluetoothPermission.restricted,
);

class _PermissionCaptureBle extends _CaptureBle
    implements LedgerBluetoothAccess {
  _PermissionCaptureBle(
    super.failure,
    this.permission, {
    this.locationPermission = false,
  });
  final bool locationPermission;
  final LedgerBluetoothPermission permission;
  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async =>
      LedgerBluetoothAccessStatus(
        failure == LedgerMobileFailure.permissionDenied
            ? permission
            : LedgerBluetoothPermission.granted,
        locationPermission: locationPermission,
        macOS: kAppFormFactor == AppFormFactor.desktop,
        bluetoothEnabled: failure != LedgerMobileFailure.bluetoothOff,
        locationEnabled: failure != LedgerMobileFailure.locationDisabled,
      );
  @override
  Future<bool> openBluetoothSettings() async => true;
}

Widget buildLedgerPermissionRestoredCapture(BuildContext context) => _signing(
  LedgerMobileFailure.permissionDenied,
  permission: LedgerBluetoothPermission.granted,
);
Widget buildLedgerLocationPermissionCapture(BuildContext context) =>
    _signing(LedgerMobileFailure.permissionDenied, locationPermission: true);

Widget buildLedgerPickerPermissionCapture(BuildContext context) =>
    ProviderScope(
      child: Builder(
        builder: (context) => MobileModalOverlay(
          background: ColoredBox(color: context.colors.background.window),
          child: MobileLedgerDeviceSheet(
            service: _PermissionCaptureBle(
              LedgerMobileFailure.permissionDenied,
              LedgerBluetoothPermission.settings,
            ),
            onSelected: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
