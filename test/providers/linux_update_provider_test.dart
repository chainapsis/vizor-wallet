import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/linux_update_provider.dart';

void main() {
  test('parses newer matching Linux update feed', () {
    final update = LinuxUpdateInfo.fromJson(
      {
        'schemaVersion': 1,
        'platform': 'linux',
        'flavor': 'mainnet',
        'version': '0.0.14',
        'assetVersion': '0.0.14',
        'buildNumber': 42,
        'releaseTag': 'release/v0.0.14',
        'releaseUrl':
            'https://github.com/chainapsis/vizor-wallet/releases/tag/release/v0.0.14',
        'assets': {
          'x86_64': {
            'appImage':
                'https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage',
            'sha256':
                'https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage.sha256',
            'signature':
                'https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage.asc',
            'zsync':
                'https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage.zsync',
          },
        },
      },
      currentBuildNumber: 41,
      expectedFlavor: 'mainnet',
      expectedArch: 'x86_64',
    );

    expect(update, isNotNull);
    expect(update!.assetVersion, '0.0.14');
    expect(update.buildNumber, 42);
    expect(update.zsyncUrl, endsWith('.zsync'));
  });

  test('ignores non-newer or mismatched Linux update feeds', () {
    final feed = {
      'schemaVersion': 1,
      'platform': 'linux',
      'flavor': 'testnet',
      'version': '0.0.14',
      'assetVersion': '0.0.14',
      'buildNumber': 42,
      'releaseTag': 'release/v0.0.14',
      'releaseUrl':
          'https://github.com/chainapsis/vizor-wallet/releases/tag/release/v0.0.14',
      'assets': {
        'x86_64': {
          'appImage': 'https://example.com/Vizor-Testnet-linux-x86_64.AppImage',
          'sha256':
              'https://example.com/Vizor-Testnet-linux-x86_64.AppImage.sha256',
          'signature':
              'https://example.com/Vizor-Testnet-linux-x86_64.AppImage.asc',
        },
      },
    };

    expect(
      LinuxUpdateInfo.fromJson(
        feed,
        currentBuildNumber: 41,
        expectedFlavor: 'mainnet',
        expectedArch: 'x86_64',
      ),
      isNull,
    );
    expect(
      LinuxUpdateInfo.fromJson(
        feed,
        currentBuildNumber: 42,
        expectedFlavor: 'testnet',
        expectedArch: 'x86_64',
      ),
      isNull,
    );
    expect(
      LinuxUpdateInfo.fromJson(
        feed,
        currentBuildNumber: 41,
        expectedFlavor: 'testnet',
        expectedArch: 'aarch64',
      ),
      isNull,
    );
  });
}
