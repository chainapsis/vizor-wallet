import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../ledger_capability.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';

class LedgerDeviceAccount {
  const LedgerDeviceAccount({
    required this.ufvk,
    required this.seedFingerprint,
    required this.accountIndex,
    required this.appVersion,
    this.transport = LedgerConnectionTransport.usb,
    this.deviceId,
    this.deviceName,
    this.deviceModel,
  });

  final String ufvk;
  final List<int> seedFingerprint;
  final int accountIndex;
  final String appVersion;
  final LedgerConnectionTransport transport;
  final String? deviceId;
  final String? deviceName;

  /// Display metadata only; this does not identify a seed or authorize signing.
  final String? deviceModel;
}

typedef LedgerAccountConnector =
    Future<LedgerDeviceAccount> Function(int accountIndex);
typedef LedgerBluetoothAccountConnector =
    Future<LedgerDeviceAccount> Function(
      int accountIndex,
      LedgerBleDevice device,
    );
typedef LedgerBluetoothSessionConnector =
    Future<String> Function(LedgerBleDevice device);
typedef LedgerMobileAccountExporter =
    Future<rust_ledger.LedgerAccountExport> Function({
      required LedgerMobileBleService mobile,
      required int accountIndex,
      required String networkName,
    });

typedef LedgerAccountImporter =
    Future<void> Function({
      required String name,
      required LedgerDeviceAccount account,
      required int birthdayHeight,
      required String profilePictureId,
    });

typedef LedgerAccountSetup =
    Future<void> Function({
      required String name,
      required LedgerDeviceAccount account,
      required int birthdayHeight,
      required String profilePictureId,
      String? pendingPassword,
    });

/// Completes account creation after the user has supplied an approved export.
/// UI callers own router-refresh suspension and navigation around this action.
final ledgerAccountSetupProvider = Provider<LedgerAccountSetup>((ref) {
  return ({
    required name,
    required account,
    required birthdayHeight,
    required profilePictureId,
    pendingPassword,
  }) async {
    final import = ref.read(ledgerAccountImporterProvider);
    Future<void> importAccount() => import(
      name: name,
      account: account,
      birthdayHeight: birthdayHeight,
      profilePictureId: profilePictureId,
    );
    if (pendingPassword == null) {
      await importAccount();
      return;
    }

    final security = ref.read(appSecurityProvider.notifier);
    var passwordPrepared = false;
    var passwordCommitted = false;
    try {
      await security.preparePasswordSetup(pendingPassword);
      passwordPrepared = true;
      await importAccount();
      security.commitPasswordSetup();
      passwordCommitted = true;
    } catch (_) {
      if (passwordPrepared && !passwordCommitted) {
        await security.rollbackPasswordSetup();
      }
      rethrow;
    }
  };
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

final ledgerBluetoothSessionConnectorProvider =
    Provider<LedgerBluetoothSessionConnector>((ref) {
      return ref.read(ledgerConnectionServiceProvider).connectBluetoothDevice;
    });

final ledgerMobileAccountExporterProvider =
    Provider<LedgerMobileAccountExporter>((_) => _exportMobileAccount);

Future<LedgerDeviceAccount> _connectLedgerAccount(
  Ref ref, {
  required int accountIndex,
  required LedgerConnectionTransport transport,
  LedgerBleDevice? bluetoothDevice,
}) async {
  ref.read(ledgerStaticCapabilityProvider).requireSupported();
  final networkName = ref.read(rpcEndpointProvider).networkName;
  final appVersion = switch (transport) {
    LedgerConnectionTransport.usb =>
      await ref
          .read(ledgerAppReadinessServiceForTransportProvider(transport))
          .ensureReady(),
    LedgerConnectionTransport.bluetooth => await ref.read(
      ledgerBluetoothSessionConnectorProvider,
    )(bluetoothDevice ?? (throw ArgumentError.notNull('bluetoothDevice'))),
  };
  final account = transport == LedgerConnectionTransport.bluetooth
      ? await ref.read(ledgerMobileAccountExporterProvider)(
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
    deviceId: bluetoothDevice?.id,
    deviceName: bluetoothDevice?.name,
    deviceModel:
        bluetoothDevice?.model ??
        (usbModel == null || usbModel.isEmpty
            ? null
            : ledgerUsbDeviceModelName(usbModel)),
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
          ledgerDeviceId: account.deviceId,
          ledgerDeviceName: account.deviceName,
          ledgerDeviceModel: account.deviceModel,
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
