import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
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
    this.walletFingerprint,
  });

  final String ufvk;
  final List<int> seedFingerprint;
  final int accountIndex;
  final String appVersion;
  final LedgerConnectionTransport transport;
  final LedgerBleDevice? device;
  final String? walletFingerprint;

  LedgerDeviceAccount withWalletIdentity(LedgerWalletIdentity identity) =>
      LedgerDeviceAccount(
        ufvk: ufvk,
        seedFingerprint: seedFingerprint,
        accountIndex: accountIndex,
        appVersion: appVersion,
        transport: transport,
        device: device,
        walletFingerprint: identity.fingerprint,
      );
}

class LedgerWalletIdentity {
  const LedgerWalletIdentity({
    required this.fingerprint,
    this.verificationAddress,
  });

  final String fingerprint;
  final String? verificationAddress;
}

typedef LedgerAccountConnector =
    Future<LedgerDeviceAccount> Function(int accountIndex);
typedef LedgerBluetoothAccountConnector =
    Future<LedgerDeviceAccount> Function(
      int accountIndex,
      LedgerBleDevice device,
    );
typedef LedgerWalletIdentityConnector =
    Future<LedgerWalletIdentity> Function(int? verificationAccountIndex);
typedef LedgerBluetoothWalletIdentityConnector =
    Future<LedgerWalletIdentity> Function(
      int? verificationAccountIndex,
      LedgerBleDevice device,
    );
typedef LedgerAccountIdentityVerifier =
    Future<bool> Function({
      required String accountUuid,
      required String deviceAddress,
    });

typedef LedgerAccountImporter =
    Future<void> Function({
      required String name,
      required LedgerDeviceAccount account,
      required int birthdayHeight,
      required String profilePictureId,
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

final ledgerWalletIdentityConnectorProvider =
    Provider<LedgerWalletIdentityConnector>((ref) {
      return (verificationAccountIndex) => _readLedgerWalletIdentity(
        ref,
        verificationAccountIndex: verificationAccountIndex,
        transport: LedgerConnectionTransport.usb,
      );
    });

final ledgerBluetoothWalletIdentityConnectorProvider =
    Provider<LedgerBluetoothWalletIdentityConnector>((ref) {
      return (verificationAccountIndex, device) => _readLedgerWalletIdentity(
        ref,
        verificationAccountIndex: verificationAccountIndex,
        transport: LedgerConnectionTransport.bluetooth,
      );
    });

final ledgerAccountIdentityVerifierProvider =
    Provider<LedgerAccountIdentityVerifier>((ref) {
      return ({required accountUuid, required deviceAddress}) async {
        final endpoint = ref.read(rpcEndpointProvider);
        final expected = await rust_ledger.ledgerAccountFirstTransparentAddress(
          dbPath: await getWalletDbPath(),
          network: endpoint.networkName,
          accountUuid: accountUuid,
        );
        return expected == deviceAddress;
      };
    });

Future<LedgerWalletIdentity> _readLedgerWalletIdentity(
  Ref ref, {
  required int? verificationAccountIndex,
  required LedgerConnectionTransport transport,
}) async {
  final capability = ref.watch(ledgerStaticCapabilityProvider);
  final networkName = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  capability.requireSupported();
  await ref
      .read(ledgerAppReadinessServiceForTransportProvider(transport))
      .ensureReady();
  final identity = transport == LedgerConnectionTransport.bluetooth
      ? await _readMobileWalletIdentity(
          mobile: ref.read(ledgerMobileBleServiceProvider),
          verificationAccountIndex: verificationAccountIndex,
          networkName: networkName,
        )
      : await rust_ledger.ledgerWalletIdentity(
          verificationAccountIndex: verificationAccountIndex,
          network: networkName,
        );
  return LedgerWalletIdentity(
    fingerprint: identity.fingerprint,
    verificationAddress: identity.verificationAddress,
  );
}

Future<rust_ledger.LedgerWalletIdentity> _readMobileWalletIdentity({
  required LedgerMobileBleService mobile,
  required int? verificationAccountIndex,
  required String networkName,
}) async {
  final plan = await rust_ledger.ledgerBuildWalletIdentityApduPlan(
    verificationAccountIndex: verificationAccountIndex,
  );
  final responses = await mobile.exchangeApdus(plan.commands);
  return rust_ledger.ledgerParseMobileWalletIdentityResponses(
    verificationAccountIndex: verificationAccountIndex,
    network: networkName,
    responses: responses,
  );
}

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
  return LedgerDeviceAccount(
    ufvk: account.ufvk,
    seedFingerprint: account.seedFingerprint,
    accountIndex: account.accountIndex,
    appVersion: appVersion,
    transport: transport,
    device: bluetoothDevice,
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
          ledgerDeviceModel: account.device?.model,
          ledgerWalletFingerprint: account.walletFingerprint,
        );
  };
});
