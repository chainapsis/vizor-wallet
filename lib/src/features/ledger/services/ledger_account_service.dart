import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../rust/api/wallet.dart' as rust_wallet;

class LedgerDeviceAccount {
  const LedgerDeviceAccount({
    required this.ufvk,
    required this.seedFingerprint,
    required this.accountIndex,
    this.transport = LedgerConnectionTransport.usb,
    this.deviceId,
    this.deviceName,
    this.deviceModel,
  });

  final String ufvk;
  final List<int> seedFingerprint;
  final int accountIndex;
  final LedgerConnectionTransport transport;
  final String? deviceId;
  final String? deviceName;

  /// Display metadata only; this does not identify a seed or authorize signing.
  final String? deviceModel;
}

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
