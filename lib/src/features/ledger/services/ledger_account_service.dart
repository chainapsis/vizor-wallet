import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import '../ledger_capability.dart';
import '../ledger_onboarding_policy.dart';
import 'ledger_app_readiness_service.dart';
import 'ledger_device_request.dart';
import 'ledger_mobile_ble_service.dart';

class LedgerDeviceAccount {
  const LedgerDeviceAccount({
    required this.ufvk,
    required this.seedFingerprint,
    required this.accountIndex,
    required this.appVersion,
    this.transport = LedgerConnectionTransport.usb,
    this.device,
  });

  final String ufvk;
  final List<int> seedFingerprint;
  final int accountIndex;
  final String appVersion;
  final LedgerConnectionTransport transport;
  final LedgerBleDevice? device;
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

final ledgerAccountConnectorProvider = Provider<LedgerAccountConnector>((ref) {
  return (accountIndex) => _connectLedgerAccount(
    ref,
    accountIndex: accountIndex,
    transport: LedgerConnectionTransport.usb,
    newAccount: true,
  );
});

final ledgerBluetoothAccountConnectorProvider =
    Provider<LedgerBluetoothAccountConnector>((ref) {
      return (accountIndex, device) => _connectLedgerAccount(
        ref,
        accountIndex: accountIndex,
        transport: LedgerConnectionTransport.bluetooth,
        bluetoothDevice: device,
        newAccount: true,
      );
    });

/// Reads an account Vizor already holds, e.g. to confirm that a different
/// Bluetooth Ledger carries it. Unlike connecting a new account, this accepts
/// every app version that can still sign.
final ledgerBluetoothExistingAccountConnectorProvider =
    Provider<LedgerBluetoothAccountConnector>((ref) {
      return (accountIndex, device) => _connectLedgerAccount(
        ref,
        accountIndex: accountIndex,
        transport: LedgerConnectionTransport.bluetooth,
        bluetoothDevice: device,
        newAccount: false,
      );
    });

Future<LedgerDeviceAccount> _connectLedgerAccount(
  Ref ref, {
  required int accountIndex,
  required LedgerConnectionTransport transport,
  required bool newAccount,
  LedgerBleDevice? bluetoothDevice,
}) async {
  final check = ref.read(ledgerDeviceRequestsProvider).capture();
  if (!isLedgerOnboardingAccountIndexValid(accountIndex)) {
    throw Exception(kLedgerOnboardingAccountIndexError);
  }
  final capability = ref.watch(ledgerStaticCapabilityProvider);
  final networkName = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  capability.requireSupported();
  if (transport == LedgerConnectionTransport.bluetooth &&
      !ledgerSupportsBluetooth(ref.read(ledgerTargetPlatformProvider))) {
    throw UnsupportedError('Connect your Ledger over USB on this platform.');
  }
  final appVersion = await ref
      .read(ledgerAppReadinessServiceForTransportProvider(transport))
      .ensureReady();
  check();
  // Refuse before asking the device to share a viewing key.
  if (newAccount && !ledgerAppVersionAllowsNewAccounts(appVersion)) {
    throw const LedgerAppReadinessException(
      LedgerAppReadinessFailure.unsupportedVersion,
      'Update the Ledger Zcash app to version '
      '$kMinimumLedgerZcashAppVersionForNewAccounts or newer.',
    );
  }
  final account = transport == LedgerConnectionTransport.bluetooth
      ? await _exportMobileAccount(
          check: check,
          mobile: ref.read(ledgerMobileBleServiceProvider),
          accountIndex: accountIndex,
          networkName: networkName,
        )
      : await rust_ledger.ledgerExportAccount(
          accountIndex: accountIndex,
          network: networkName,
        );
  check();
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
  required void Function() check,
  required LedgerMobileBleService mobile,
  required int accountIndex,
  required String networkName,
}) async {
  final plan = await rust_ledger.ledgerBuildUfvkApduPlan(
    accountIndex: accountIndex,
  );
  check();
  final responses = await mobile.exchangeUfvk(plan);
  check();
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
        );
  };
});
