import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_secure_store.dart';

const kPaymentLinkClaimWalletDirectoryPrefix = 'payment_link_claim_';

/// Claim-wallet directories are named
/// `payment_link_claim_<network>_<sha256>`. The hash cannot be reversed, so the
/// network segment is the only thing that lets a sweep delete one network's
/// claim wallets without touching another's retained recovery state.
final _paymentLinkClaimWalletDirectoryPattern = RegExp(
  r'^payment_link_claim_[a-z0-9]+_[0-9a-f]{64}$',
);

String paymentLinkClaimWalletDirectoryNameFor({
  required String network,
  required String identityHash,
}) => '$kPaymentLinkClaimWalletDirectoryPrefix${network}_$identityHash';

RegExp _paymentLinkClaimWalletDirectoryPatternFor(String network) => RegExp(
  '^$kPaymentLinkClaimWalletDirectoryPrefix'
  '${RegExp.escape(network)}_[0-9a-f]{64}\$',
);

/// Set by integration runners whose tests share the installed app's bundle
/// identifier and network (the Ledger Speculos lanes run on mainnet). Such a
/// build must never resolve the installed app's wallet storage: an unset
/// [debugWalletStorageDirectory] then fails the test instead of opening, and
/// migrating, the user's real wallet.
const _requireIsolatedWalletStorage = bool.fromEnvironment(
  'VIZOR_E2E_REQUIRE_ISOLATED_WALLET_STORAGE',
);

/// Wallet DB file name used inside [debugWalletStorageDirectory].
@visibleForTesting
const kDebugWalletDbName = 'wallet.db';

/// Test-only wallet storage root. When set, every wallet storage path resolves
/// inside it and the wallet DB is [kDebugWalletDbName]; neither the app
/// container nor the keychain-held DB name is consulted.
@visibleForTesting
Directory? debugWalletStorageDirectory;

Directory? _isolatedWalletStorageDirectory() {
  final directory = debugWalletStorageDirectory;
  if (directory == null && _requireIsolatedWalletStorage) {
    final error = StateError(
      'This E2E build resolved the installed app wallet storage. Set '
      'debugWalletStorageDirectory to the scenario sandbox.',
    );
    // Callers such as ownAccountAddressesProvider treat a failed lookup as
    // best-effort, so report it where the test binding fails the test.
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, library: 'wallet storage'),
    );
    throw error;
  }
  return directory;
}

Future<Directory> getWalletSupportDirectory() async {
  final dir =
      _isolatedWalletStorageDirectory() ??
      await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return dir;
}

Future<String> getWalletDbName() async {
  if (_isolatedWalletStorageDirectory() != null) return kDebugWalletDbName;
  return AppSecureStore.instance.ensureWalletDbName();
}

Future<String> getWalletDbPath() async {
  final dir = await getWalletSupportDirectory();
  final dbName = await getWalletDbName();
  return '${dir.path}${Platform.pathSeparator}$dbName';
}

Future<String> getTorDataDirectoryPath() async {
  final dir = await getWalletSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}tor';
}

/// Deletes claim-wallet directories for [network] only, or for every network
/// when it is null.
Future<void> deletePaymentLinkClaimWalletDirectories({
  String? network,
  Future<Directory> Function() resolveSupportDirectory =
      getWalletSupportDirectory,
  Future<void> Function(Directory directory)? deleteDirectory,
}) async {
  final pattern = network == null
      ? _paymentLinkClaimWalletDirectoryPattern
      : _paymentLinkClaimWalletDirectoryPatternFor(network);
  final supportDirectory = await resolveSupportDirectory();
  if (!await supportDirectory.exists()) return;

  Object? firstError;
  StackTrace? firstStackTrace;
  await for (final entity in supportDirectory.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final directoryName = entity.path.split(Platform.pathSeparator).last;
    if (!pattern.hasMatch(directoryName)) {
      continue;
    }
    try {
      if (deleteDirectory == null) {
        await entity.delete(recursive: true);
      } else {
        await deleteDirectory(entity);
      }
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

/// Scoped to both the wallet instance and network; never overlaps claim DBs.
Future<String> getGiftCardTrackingDbPath(String network) async {
  if (!RegExp(r'^[a-z0-9]+$').hasMatch(network)) {
    throw ArgumentError.value(network, 'network');
  }
  final support = await getWalletSupportDirectory();
  final walletName = await getWalletDbName();
  final directory = Directory(
    '${support.path}${Platform.pathSeparator}gift_card_tracking_${walletName}_$network',
  );
  await directory.create(recursive: true);
  return '${directory.path}${Platform.pathSeparator}observer.db';
}

Future<void> deleteGiftCardTrackingDirectories() async {
  final support = await getWalletSupportDirectory();
  await for (final entity in support.list(followLinks: false)) {
    if (entity is Directory &&
        entity.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('gift_card_tracking_')) {
      await entity.delete(recursive: true);
    }
  }
}
