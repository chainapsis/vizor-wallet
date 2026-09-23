import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;
import 'ledger_account_service.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_bluetooth_access.dart';
import 'ledger_connection_service.dart';
import 'ledger_device_request.dart';
import 'ledger_mobile_ble_service.dart';
import 'ledger_operation_lifecycle.dart';
import 'ledger_signing_service.dart';

/// Remember intermediate lock/account changes, even if the user switches back
/// before a pending device response arrives.
final ledgerPairingRecoverySessionProvider = Provider((ref) {
  var generation = 0;
  ref.listen(
    accountProvider.select((value) => value.value?.activeAccountUuid),
    (_, _) => generation++,
  );
  ref.listen(appSecurityProvider, (_, _) => generation++);
  void Function() capture() {
    final captured = generation;
    void check() {
      if (captured != generation ||
          ref.read(appSecurityProvider).requiresUnlock) {
        throw const LedgerMobileException(
          LedgerMobileFailure.cancelled,
          'The wallet changed. Close this screen and try again.',
        );
      }
    }

    check();
    return check;
  }

  return capture;
});

/// A discovery identifier is a connection hint, never proof of account identity.
bool ledgerDeviceDiffersFromSavedConnection(String? savedId, String deviceId) =>
    savedId != null && savedId.isNotEmpty && savedId != deviceId;

/// A saved connection may skip viewing-key approval. Signing still validates
/// returned signatures; this does not assert the device's current seed.
bool ledgerDeviceMatchesSavedConnection(String? savedId, String deviceId) =>
    savedId != null && savedId.isNotEmpty && savedId == deviceId;

class LedgerAccountMismatchException implements Exception {
  const LedgerAccountMismatchException();
}

typedef LedgerRecoveryAccountKeyLoader = Future<String> Function(String uuid);
final ledgerRecoveryAccountKeyLoaderProvider =
    Provider<LedgerRecoveryAccountKeyLoader>(
      (ref) => (uuid) async {
        final dbPath = await ref.read(ledgerWalletDbPathProvider)();
        return rust_wallet.getAccountUfvk(
          dbPath: dbPath,
          network: ref.read(rpcEndpointProvider).networkName,
          accountUuid: uuid,
        );
      },
    );

final ledgerPairingRecoveryServiceProvider = Provider(
  LedgerPairingRecoveryService.new,
);

/// Rebinds only after exporting and comparing the complete account viewing key.
/// Device names, model names and Bluetooth identifiers are not account identity.
/// A matching saved ID reconnects with app readiness only; no rebind is needed.
class LedgerPairingRecoveryService {
  LedgerPairingRecoveryService(this.ref);
  final Ref ref;

  /// Returns whether a previously saved device ID was replaced, only after
  /// verification and persistence both succeed.
  Future<bool> verifyAndSave({
    required String accountUuid,
    required LedgerBleDevice device,
    required void Function() checkCurrent,
    required void Function() onSaving,
  }) => ref
      .read(ledgerConnectionServiceProvider)
      .recover(
        () => verifyAndSaveWithinConnection(
          accountUuid: accountUuid,
          device: device,
          checkCurrent: checkCurrent,
          onSaving: onSaving,
        ),
      );

  /// Caller must hold the connection service's operation exclusion.
  Future<bool> verifyAndSaveWithinConnection({
    required String accountUuid,
    required LedgerBleDevice device,
    required void Function() checkCurrent,
    required void Function() onSaving,
  }) async {
    final epoch = ref.read(ledgerDeviceRequestsProvider).capture();
    final session = ref.read(ledgerPairingRecoverySessionProvider)();
    void check() {
      epoch();
      session();
      checkCurrent();
    }

    check();
    final account = ref
        .read(accountProvider)
        .value
        ?.accounts
        .where((a) => a.uuid == accountUuid && a.isLedger)
        .firstOrNull;
    if (account == null || account.zip32AccountIndex == null) {
      throw StateError(
        'This Ledger account is missing its derivation information.',
      );
    }
    final lifecycle = ref.read(ledgerOperationLifecycleProvider);
    final sameDevice = ledgerDeviceMatchesSavedConnection(
      account.ledgerDeviceId,
      device.id,
    );
    final expected = sameDevice
        ? null
        : await lifecycle.run(
            () => ref.read(ledgerRecoveryAccountKeyLoaderProvider)(accountUuid),
          );
    check();
    final mobile = ref.read(ledgerMobileBleServiceProvider);
    await requireLedgerBluetoothAccess(mobile);
    check();
    await mobile.stopDiscovery();
    check();
    await mobile.disconnect();
    check();
    await mobile.connect(device);
    check();
    if (sameDevice) {
      await ref
          .read(
            ledgerAppReadinessServiceForTransportProvider(
              LedgerConnectionTransport.bluetooth,
            ),
          )
          .ensureReady();
      check();
      return false;
    }
    // This requests viewing-key approval, never a transaction signature.
    final exported = await ref.read(
      ledgerBluetoothExistingAccountConnectorProvider,
    )(account.zip32AccountIndex!, device);
    check();
    if (expected == null ||
        expected.isEmpty ||
        exported.ufvk != expected ||
        exported.accountIndex != account.zip32AccountIndex) {
      throw const LedgerAccountMismatchException();
    }
    // Device approval stays outside the durable mutation drain. Once verified,
    // deletion must wait for this short metadata commit to finish.
    await lifecycle.run(() async {
      check();
      onSaving();
      await ref
          .read(accountProvider.notifier)
          .recordLedgerConnection(
            uuid: accountUuid,
            transport: LedgerConnectionTransport.bluetooth,
            deviceId: device.id,
            deviceName: device.name,
            deviceModel: device.model,
          );
    });
    check();
    return ledgerDeviceDiffersFromSavedConnection(
      account.ledgerDeviceId,
      device.id,
    );
  }
}
