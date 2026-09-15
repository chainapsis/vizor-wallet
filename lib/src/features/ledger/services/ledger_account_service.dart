import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../ledger_capability.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_mobile_ble_service.dart';

class LedgerDeviceAccount {
  const LedgerDeviceAccount({
    required this.ufvk,
    required this.seedFingerprint,
    required this.accountIndex,
    required this.appVersion,
    this.transport = LedgerConnectionTransport.usb,
    this.device,
    this.deviceModel,
  });

  final String ufvk;
  final List<int> seedFingerprint;
  final int accountIndex;
  final String appVersion;
  final LedgerConnectionTransport transport;
  final LedgerBleDevice? device;

  /// Model of a USB device; Bluetooth devices carry it in [device].
  final String? deviceModel;
}

typedef LedgerAccountConnector =
    Future<LedgerDeviceAccount> Function(int accountIndex);
typedef LedgerBluetoothAccountConnector =
    Future<LedgerDeviceAccount> Function(
      int accountIndex,
      LedgerBleDevice device,
    );
typedef LedgerAccountImporter =
    Future<void> Function({
      required String name,
      required LedgerDeviceAccount account,
      required int birthdayHeight,
      required String profilePictureId,
    });

final ledgerAccountUfvkLoaderProvider =
    Provider<Future<String> Function(String)>((ref) {
      return (uuid) async {
        final network = ref.read(rpcEndpointProvider).networkName;
        return rust_wallet.getAccountUfvk(
          dbPath: await getWalletDbPath(),
          network: network,
          accountUuid: uuid,
        );
      };
    });

final ledgerAccountConnectorProvider = Provider<LedgerAccountConnector>((ref) {
  return (accountIndex) => _connectLedgerAccount(
    ref,
    accountIndex: accountIndex,
    transport: LedgerConnectionTransport.usb,
  );
});

final ledgerBluetoothAccountConnectorProvider =
    Provider<LedgerBluetoothAccountConnector>((ref) {
      return (accountIndex, device) => _connectLedgerAccount(
        ref,
        accountIndex: accountIndex,
        transport: LedgerConnectionTransport.bluetooth,
        bluetoothDevice: device,
      );
    });

Future<LedgerDeviceAccount> _connectLedgerAccount(
  Ref ref, {
  required int accountIndex,
  required LedgerConnectionTransport transport,
  LedgerBleDevice? bluetoothDevice,
}) async {
  final capability = ref.watch(ledgerStaticCapabilityProvider);
  final networkName = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  capability.requireSupported();
  final appVersion = await ref
      .read(ledgerAppReadinessServiceForTransportProvider(transport))
      .ensureReady();
  final account = transport == LedgerConnectionTransport.bluetooth
      ? await _exportMobileAccount(
          mobile: ref.read(ledgerMobileBleServiceProvider),
          accountIndex: accountIndex,
          networkName: networkName,
        )
      : await rust_ledger.ledgerExportAccount(
          accountIndex: accountIndex,
          network: networkName,
        );
  final usbModel = account.deviceModel?.trim();
  return LedgerDeviceAccount(
    ufvk: account.ufvk,
    seedFingerprint: account.seedFingerprint,
    accountIndex: account.accountIndex,
    appVersion: appVersion,
    transport: transport,
    device: bluetoothDevice,
    deviceModel: usbModel == null || usbModel.isEmpty
        ? null
        : ledgerUsbDeviceModelName(usbModel),
  );
}

Future<rust_ledger.LedgerAccountExport> _exportMobileAccount({
  required LedgerMobileBleService mobile,
  required int accountIndex,
  required String networkName,
}) async {
  final plan = await rust_ledger.ledgerBuildUfvkApduPlan(
    accountIndex: accountIndex,
  );
  final responses = await mobile.exchangeUfvk(plan);
  return rust_ledger.ledgerParseMobileUfvkResponses(
    accountIndex: accountIndex,
    network: networkName,
    responses: responses,
  );
}

final ledgerAccountImporterProvider = Provider<LedgerAccountImporter>((ref) {
  return ({
    required name,
    required account,
    required birthdayHeight,
    required profilePictureId,
  }) {
    return ref
        .read(accountProvider.notifier)
        .importLedgerAccount(
          name: name,
          ufvk: account.ufvk,
          seedFingerprint: account.seedFingerprint,
          zip32Index: account.accountIndex,
          birthdayHeight: birthdayHeight,
          profilePictureId: profilePictureId,
          connectionTransport: account.transport,
          ledgerDeviceId: account.device?.id,
          ledgerDeviceName: account.device?.name,
          ledgerDeviceModel: account.device?.model ?? account.deviceModel,
        );
  };
});

class LedgerDuplicateAccountException implements Exception {
  const LedgerDuplicateAccountException();

  @override
  String toString() => 'This Ledger account is already in Vizor.';
}

final ledgerAccountDuplicateCheckerProvider =
    Provider<Future<void> Function(String)>((ref) {
      return (ufvk) async {
        final accounts = (await ref.read(accountProvider.future)).accounts;
        final loadUfvk = ref.read(ledgerAccountUfvkLoaderProvider);
        for (final account in accounts) {
          if (await loadUfvk(account.uuid) == ufvk) {
            throw const LedgerDuplicateAccountException();
          }
        }
      };
    });
