// Deterministic recovery interactions: no wallet data, Rust, or native IO.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/ledger/ledger_capability.dart';
import '../src/features/ledger/services/ledger_account_service.dart';
import '../src/features/ledger/services/ledger_bluetooth_access.dart';
import '../src/features/ledger/services/ledger_mobile_ble_service.dart';
import '../src/features/ledger/services/ledger_pairing_recovery_service.dart';
import '../src/features/ledger/services/ledger_signing_service.dart';
import '../src/features/ledger/widgets/ledger_access_recovery_modal.dart';
import '../src/features/ledger/widgets/mobile_ledger_signing_surface.dart';
import '../src/providers/account_provider.dart';
import '../src/providers/app_security_provider.dart';

const _account = AccountInfo(
  uuid: 'capture',
  name: 'Ledger',
  order: 0,
  isHardware: true,
  hardwareSignerKind: HardwareSignerKind.ledger,
  zip32AccountIndex: 0,
  ledgerDeviceId: 'old',
  ledgerDeviceModel: 'Flex',
);

Widget buildLedgerRePairingCapture(BuildContext context) {
  final mobile = kAppFormFactor == AppFormFactor.mobile;
  const modal = LedgerAccessRecoveryModal(
    account: _account,
    pairingRecovery: true,
    onRetry: _noop,
    onClose: _noop,
  );
  return ProviderScope(
    overrides: [
      accountProvider.overrideWith(_Accounts.new),
      appSecurityProvider.overrideWith(_Security.new),
      ledgerTargetPlatformProvider.overrideWithValue(
        mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
      ledgerMobileBleServiceProvider.overrideWithValue(_Ble()),
      ledgerRecoveryAccountKeyLoaderProvider.overrideWithValue(
        (_) async => 'expected',
      ),
      ledgerBluetoothAccountConnectorProvider.overrideWithValue(
        (index, device) async => LedgerDeviceAccount(
          ufvk: device.id == 'flex' ? 'expected' : 'different',
          seedFingerprint: const [],
          accountIndex: index,
          appVersion: '1',
        ),
      ),
      ledgerRustOperationCancellerProvider.overrideWithValue(() async {}),
    ],
    child: mobile
        ? const MobileLedgerSigningSurface(
            title: 'Confirm transaction',
            onBack: _noop,
            canLeave: true,
            child: modal,
          )
        : ColoredBox(
            color: context.colors.background.window,
            child: const Center(child: modal),
          ),
  );
}

void _noop() {}

class _Accounts extends AccountNotifier {
  @override
  AccountState build() =>
      const AccountState(accounts: [_account], activeAccountUuid: 'capture');
  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {}
  @override
  Future<void> updateLedgerConnectionPreference(
    String uuid,
    LedgerConnectionPreference preference,
  ) async {}
}

class _Ble
    implements
        LedgerMobileBleService,
        LedgerBluetoothAccess,
        LedgerBluetoothPairingSettings {
  @override
  String? connectedDeviceId;
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> disconnect() async {
    connectedDeviceId = null;
  }

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectedDeviceId = device.id;
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => Stream.fromIterable(const [
    LedgerDevicesDiscovered([
      LedgerBleDevice(id: 'flex', name: 'Ledger Flex', model: 'Flex'),
      LedgerBleDevice(id: 'nano', name: 'Ledger Nano X', model: 'Nano X'),
    ]),
    LedgerDiscoveryEnded(),
  ]);
  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async =>
      const LedgerBluetoothAccessStatus(LedgerBluetoothPermission.granted);
  @override
  Future<bool> openBluetoothPairingSettings() async => true;
  @override
  Future<bool> openBluetoothSettings() async => true;
  @override
  Future<void> cancelSigning() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected capture IO: ${invocation.memberName}');
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}
