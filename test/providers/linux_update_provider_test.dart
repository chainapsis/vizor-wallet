import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/providers/linux_update_provider.dart';

void main() {
  test(
    'checks the Linux release feed through the configured network route',
    () async {
      final bridge = _LinuxUpdateTorBridge(
        response: NetworkHttpResponse(
          statusCode: HttpStatus.ok,
          bodyBytes: Uint8List.fromList(
            '''
{
  "schemaVersion": 1,
  "platform": "linux",
  "flavor": "mainnet",
  "version": "0.0.14",
  "assetVersion": "0.0.14",
  "buildNumber": 42,
  "releaseTag": "release/v0.0.14",
  "releaseUrl": "https://github.com/chainapsis/vizor-wallet/releases/tag/release/v0.0.14",
  "assets": {
    "x86_64": {
      "appImage": "https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage",
      "sha256": "https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage.sha256",
      "signature": "https://github.com/chainapsis/vizor-wallet/releases/download/release/v0.0.14/Vizor-linux-x86_64.AppImage.asc"
    }
  }
}
'''
                .codeUnits,
          ),
        ),
      );

      final update = await fetchLinuxUpdate(
        clientFactory: () =>
            NetworkHttpClient(torDesired: () => true, torBridge: bridge),
        repository: 'chainapsis/vizor-wallet',
        flavor: 'mainnet',
        arch: 'x86_64',
        currentBuildNumber: 41,
      );

      expect(update?.buildNumber, 42);
      expect(bridge.requests, [
        Uri.parse(
          'https://github.com/chainapsis/vizor-wallet/releases/latest/'
          'download/linux-update.json',
        ),
      ]);
      expect(
        bridge.headers.single[HttpHeaders.acceptHeader],
        'application/json',
      );
    },
  );

  test(
    'a slow Linux release feed times out without blocking startup',
    () async {
      final bridge = _LinuxUpdateTorBridge(waitForever: true);

      final update = await fetchLinuxUpdate(
        clientFactory: () =>
            NetworkHttpClient(torDesired: () => true, torBridge: bridge),
        repository: 'chainapsis/vizor-wallet',
        flavor: 'mainnet',
        arch: 'x86_64',
        currentBuildNumber: 41,
        timeout: const Duration(milliseconds: 10),
      );

      expect(update, isNull);
      expect(bridge.requests, hasLength(1));
    },
  );

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

class _LinuxUpdateTorBridge implements TorHttpBridge {
  _LinuxUpdateTorBridge({this.response, this.waitForever = false});

  final NetworkHttpResponse? response;
  final bool waitForever;
  final requests = <Uri>[];
  final headers = <Map<String, String>>[];

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) {
    requests.add(uri);
    this.headers.add(Map<String, String>.of(headers));
    if (waitForever) return Completer<NetworkHttpResponse>().future;
    return Future.value(response!);
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) => throw UnimplementedError();

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) => throw UnimplementedError();
}
