// These platform interfaces are transitive app dependencies.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Holds wallet-path resolution unresolved, so a pre-navigation read would
/// prevent the receipt from opening instead of failing fast on an absent plugin.
class WalletPathReadBlocker extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  WalletPathReadBlocker() {
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = this;
    addTearDown(() => PathProviderPlatform.instance = previous);
  }

  final _path = Completer<String?>();

  @override
  Future<String?> getApplicationSupportPath() {
    return _path.future;
  }
}
