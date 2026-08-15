import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// path_provider exposes its platform interface through this transitive package.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

void main() {
  test(
    'support directory resolution is cached and retries after failure',
    () async {
      final originalPlatform = PathProviderPlatform.instance;
      final tempRoot = await Directory.systemTemp.createTemp(
        'vizor-wallet-paths-test-',
      );
      final supportPath = [
        tempRoot.path,
        'application-support',
      ].join(Platform.pathSeparator);
      final platform = _RetryingPathProviderPlatform(supportPath);
      PathProviderPlatform.instance = platform;

      try {
        await expectLater(getWalletSupportDirectory(), throwsStateError);

        final first = await getWalletSupportDirectory();
        final second = await getWalletSupportDirectory();

        expect(first.path, supportPath);
        expect(identical(first, second), isTrue);
        expect(await first.exists(), isTrue);
        expect(platform.applicationSupportCalls, 2);
      } finally {
        resetWalletSupportDirectoryCacheForTesting();
        PathProviderPlatform.instance = originalPlatform;
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      }
    },
  );
}

class _RetryingPathProviderPlatform extends PathProviderPlatform {
  _RetryingPathProviderPlatform(this.applicationSupportPath);

  final String applicationSupportPath;
  var applicationSupportCalls = 0;

  @override
  Future<String?> getApplicationSupportPath() async {
    applicationSupportCalls += 1;
    if (applicationSupportCalls == 1) {
      throw StateError('forced path resolution failure');
    }
    return applicationSupportPath;
  }
}
