import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'app_secure_store.dart';

const kPaymentLinkClaimWalletDirectoryPrefix = 'payment_link_claim_';

/// Overrides where wallet DB, Tor data, and other wallet-support files are
/// stored (#145: running a portable install off a USB/NVMe drive). Desktop
/// only. Set once at startup by [configureWalletDataDirectoryOverride] from
/// a `--wallet-data-dir` CLI argument -- forwarded to Dart's `main()` by the
/// generated Linux and Windows runners -- or the `VIZOR_WALLET_DATA_DIR`
/// environment variable, which also covers macOS, where argv is not
/// forwarded to Dart by this app's runner.
String? _walletDataDirectoryOverride;

const _walletDataDirArgPrefix = '--wallet-data-dir';
const _walletDataDirEnvVar = 'VIZOR_WALLET_DATA_DIR';

/// Call once from `main()`, before any wallet path is resolved. A no-op on
/// mobile, where there is no meaningful CLI/environment invocation to read.
void configureWalletDataDirectoryOverride(List<String> args) {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('$_walletDataDirArgPrefix=')) {
      _setWalletDataDirectoryOverride(
        arg.substring(_walletDataDirArgPrefix.length + 1),
      );
      return;
    }
    if (arg == _walletDataDirArgPrefix && i + 1 < args.length) {
      _setWalletDataDirectoryOverride(args[i + 1]);
      return;
    }
  }

  final fromEnv = Platform.environment[_walletDataDirEnvVar];
  if (fromEnv != null) {
    _setWalletDataDirectoryOverride(fromEnv);
  }
}

void _setWalletDataDirectoryOverride(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;
  _walletDataDirectoryOverride = trimmed;
}

@visibleForTesting
String? get walletDataDirectoryOverrideForTesting =>
    _walletDataDirectoryOverride;

@visibleForTesting
void resetWalletDataDirectoryOverrideForTesting() {
  _walletDataDirectoryOverride = null;
}

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
  final overridePath = _walletDataDirectoryOverride;
  final dir = overridePath == null
      ? await getApplicationSupportDirectory()
      : Directory(overridePath);
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
