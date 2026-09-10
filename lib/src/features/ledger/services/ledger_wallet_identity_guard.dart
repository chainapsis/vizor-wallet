import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../rust/api/ledger.dart' as rust_ledger;
import '../ledger_error_messages.dart' show kLedgerWrongWalletMessage;
import 'ledger_account_service.dart' show readMobileLedgerWalletIdentity;
import 'ledger_mobile_ble_service.dart';

/// The connected Ledger is not the wallet this account was imported from.
///
/// Raised before any approval is requested, so the user never approves a
/// transaction whose signatures cannot match the account.
class LedgerWrongWalletException implements Exception {
  const LedgerWrongWalletException();

  @override
  String toString() => kLedgerWrongWalletMessage;
}

typedef LedgerUsbWalletFingerprintReader =
    Future<String> Function(String network);
typedef LedgerBluetoothWalletFingerprintReader =
    Future<String> Function(LedgerMobileBleService mobile, String network);

/// Verifies the connected device against [accountUuid]'s stored wallet
/// fingerprint. Pass [mobile] when the request runs over Bluetooth so the
/// identity is read on that connection.
typedef LedgerWalletIdentityGuard =
    Future<void> Function(String accountUuid, {LedgerMobileBleService? mobile});

final ledgerUsbWalletFingerprintReaderProvider =
    Provider<LedgerUsbWalletFingerprintReader>((_) {
      return (network) async => (await rust_ledger.ledgerWalletIdentity(
        network: network,
      )).fingerprint;
    });

final ledgerBluetoothWalletFingerprintReaderProvider =
    Provider<LedgerBluetoothWalletFingerprintReader>((_) {
      return (mobile, network) async => (await readMobileLedgerWalletIdentity(
        mobile: mobile,
        networkName: network,
      )).fingerprint;
    });

/// Accounts imported before the wallet fingerprint existed have nothing to
/// compare against and are not checked; Rust still rejects their signatures
/// after the fact.
String? ledgerWalletFingerprintForAccount(
  Iterable<AccountInfo>? accounts,
  String accountUuid,
) {
  for (final account in accounts ?? const <AccountInfo>[]) {
    if (account.uuid != accountUuid) continue;
    if (!account.hasLedgerWalletIdentity) return null;
    return account.ledgerWalletFingerprint!.trim().toLowerCase();
  }
  return null;
}

final ledgerWalletIdentityGuardProvider = Provider<LedgerWalletIdentityGuard>((
  ref,
) {
  final network = ref.watch(
    rpcEndpointProvider.select((endpoint) => endpoint.networkName),
  );
  final readUsb = ref.watch(ledgerUsbWalletFingerprintReaderProvider);
  final readBluetooth = ref.watch(
    ledgerBluetoothWalletFingerprintReaderProvider,
  );
  return (accountUuid, {mobile}) async {
    final expected = ledgerWalletFingerprintForAccount(
      ref.read(accountProvider).value?.accounts,
      accountUuid,
    );
    if (expected == null) return;
    final actual = mobile == null
        ? await readUsb(network)
        : await readBluetooth(mobile, network);
    if (actual.trim().toLowerCase() != expected) {
      throw const LedgerWrongWalletException();
    }
  };
});
