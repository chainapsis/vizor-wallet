import 'dart:io';

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

Future<Directory> getWalletSupportDirectory() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return dir;
}

Future<String> getWalletDbName() async {
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
