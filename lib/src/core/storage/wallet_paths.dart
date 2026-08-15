import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'app_secure_store.dart';

Future<Directory>? _walletSupportDirectoryFuture;

Future<Directory> getWalletSupportDirectory() {
  final cached = _walletSupportDirectoryFuture;
  if (cached != null) return cached;

  late final Future<Directory> pending;
  pending = _resolveWalletSupportDirectory().onError((error, stackTrace) {
    if (identical(_walletSupportDirectoryFuture, pending)) {
      _walletSupportDirectoryFuture = null;
    }
    Error.throwWithStackTrace(error!, stackTrace);
  });
  _walletSupportDirectoryFuture = pending;
  return pending;
}

Future<Directory> _resolveWalletSupportDirectory() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return dir;
}

@visibleForTesting
void resetWalletSupportDirectoryCacheForTesting() {
  _walletSupportDirectoryFuture = null;
}

Future<String> getWalletDbName() async {
  return AppSecureStore.instance.ensureWalletDbName();
}

Future<String> getWalletDbPath() async {
  final pathParts = await Future.wait<Object>([
    getWalletSupportDirectory(),
    getWalletDbName(),
  ]);
  final dir = pathParts[0] as Directory;
  final dbName = pathParts[1] as String;
  return '${dir.path}${Platform.pathSeparator}$dbName';
}

Future<String> getTorDataDirectoryPath() async {
  final dir = await getWalletSupportDirectory();
  return '${dir.path}${Platform.pathSeparator}tor';
}
