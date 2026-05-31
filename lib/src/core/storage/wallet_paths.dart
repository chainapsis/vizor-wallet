import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_secure_store.dart';

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

/// Path for the voting sidecar database associated with a wallet DB.
///
/// The sidecar is deleted with the wallet DB during reset/delete flows so
/// voting state cannot survive after the wallet accounts are gone.
String votingDbPathForWalletDbPath(String walletDbPath) {
  return '$walletDbPath.voting';
}
