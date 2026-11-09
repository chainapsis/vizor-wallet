import 'dart:async';

import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

class LedgerAccessFake
    implements LedgerMobileBleService, LedgerBluetoothAccess {
  LedgerBluetoothAccessStatus status = const LedgerBluetoothAccessStatus(
    LedgerBluetoothPermission.restricted,
    macOS: true,
  );
  Completer<LedgerBluetoothAccessStatus>? pendingStatus;
  Completer<bool>? pendingSettings;
  bool opensSettings = true;
  int settings = 0, requests = 0, discoveries = 0, disconnects = 0;
  Object? disconnectError;

  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async =>
      pendingStatus?.future ?? status;
  @override
  Future<bool> openBluetoothSettings() async {
    settings++;
    return pendingSettings?.future ?? opensSettings;
  }

  @override
  Future<bool> requestPermissions() async {
    requests++;
    return false;
  }

  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> disconnect() async {
    disconnects++;
    if (disconnectError case final error?) throw error;
  }

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() {
    discoveries++;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Ledger operation: ${invocation.memberName}');
}
