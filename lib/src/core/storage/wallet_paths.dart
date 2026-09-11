import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_secure_store.dart';

const _walletDbNameOverride = String.fromEnvironment('VIZOR_WALLET_DB_NAME');

Future<Directory> getWalletSupportDirectory() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return dir;
}

Future<String> getWalletDbName() async {
  if (_walletDbNameOverride.isNotEmpty) return _walletDbNameOverride;
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
