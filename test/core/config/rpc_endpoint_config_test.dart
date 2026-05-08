import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';

void main() {
  group('normalizeRpcEndpointUrl', () {
    test('normalizes host and explicit port with an https scheme', () {
      expect(normalizeRpcEndpointUrl('zec.rocks:443'), 'https://zec.rocks:443');
      expect(
        normalizeRpcEndpointUrl('https://zec.rocks:443'),
        'https://zec.rocks:443',
      );
    });

    test('rejects missing ports unless default ports are allowed', () {
      expect(
        () => normalizeRpcEndpointUrl('zec.rocks'),
        throwsA(isA<FormatException>()),
      );
      expect(
        normalizeRpcEndpointUrl('zec.rocks', allowDefaultPort: true),
        'https://zec.rocks:443',
      );
    });

    test('rejects invalid ports and spaces', () {
      expect(
        () => normalizeRpcEndpointUrl('zec.rocks:70000'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => normalizeRpcEndpointUrl('zec.rocks:abc'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => normalizeRpcEndpointUrl('zec.rocks :443'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-local http endpoints', () {
      expect(
        () => normalizeRpcEndpointUrl('http://zec.rocks:443'),
        throwsA(isA<FormatException>()),
      );
      expect(
        normalizeRpcEndpointUrl('http://127.0.0.1:9067'),
        'http://127.0.0.1:9067',
      );
    });

    test('allows Android emulator host as local http in debug mode', () {
      expect(
        normalizeRpcEndpointUrl('http://10.0.2.2:9067'),
        'http://10.0.2.2:9067',
      );
    });

    test('preserves bracketed IPv6 host formatting', () {
      expect(
        normalizeRpcEndpointUrl('https://[::1]:9067'),
        'https://[::1]:9067',
      );
    });
  });

  group('preset lookup', () {
    test('mainnet presets include the regional endpoint list', () {
      final urls = kMainnetRpcEndpointPresets
          .map((preset) => preset.url)
          .map((url) => normalizeRpcEndpointUrl(url, allowDefaultPort: true))
          .toSet();

      expect(urls, {
        'https://us.zec.stardust.rest:443',
        'https://eu.zec.stardust.rest:443',
        'https://eu2.zec.stardust.rest:443',
        'https://jp.zec.stardust.rest:443',
        'https://zec.rocks:443',
        'https://na.zec.rocks:443',
        'https://sa.zec.rocks:443',
        'https://eu.zec.rocks:443',
        'https://ap.zec.rocks:443',
        'https://z3.deepikaw.xyz:443',
        'https://zprivacy.online:443',
        'https://lwd.zcashexplorer.app:9067',
      });
    });

    test('mainnet presets expose expected regions for endpoint selection', () {
      expect(
        findRpcEndpointPresetByUrl(
          'us.zec.stardust.rest:443',
          networkName: 'main',
        )?.region,
        'Default',
      );
      expect(
        findRpcEndpointPresetByUrl(
          'eu.zec.stardust.rest:443',
          networkName: 'main',
        )?.region,
        'Europe',
      );
      expect(
        findRpcEndpointPresetByUrl(
          'jp.zec.stardust.rest:443',
          networkName: 'main',
        )?.region,
        'Asia Pacific',
      );
    });

    test('testnet presets include the default and community fallback', () {
      final urls = kTestnetRpcEndpointPresets
          .map((preset) => preset.url)
          .map((url) => normalizeRpcEndpointUrl(url, allowDefaultPort: true))
          .toSet();

      expect(urls, {
        'https://testnet.zec.rocks:443',
        'https://zcash.mysideoftheweb.com:19067',
      });
      expect(
        findRpcEndpointPresetByUrl(
          'zcash.mysideoftheweb.com:19067',
          networkName: 'test',
        )?.id,
        'mysideoftheweb-testnet',
      );
    });

    test('matches normalized URLs within the requested network', () {
      final preset = findRpcEndpointPresetByUrl(
        'us.zec.stardust.rest',
        networkName: 'main',
      );

      expect(preset?.id, kDefaultRpcEndpointPresetId);
    });

    test('keeps the previous zec.rocks default as a selectable fallback', () {
      final preset = findRpcEndpointPresetByUrl(
        'zec.rocks',
        networkName: 'main',
      );

      expect(preset?.id, 'zec-rocks');
    });

    test('does not cross-match testnet URLs when mainnet is requested', () {
      final preset = findRpcEndpointPresetByUrl(
        'testnet.zec.rocks:443',
        networkName: 'main',
      );

      expect(preset, isNull);
    });

    test('includes a local regtest default preset', () {
      final defaultEndpoint = defaultRpcEndpointConfig('regtest');

      expect(defaultEndpoint.networkName, 'regtest');
      expect(defaultEndpoint.lightwalletdUrl, 'http://127.0.0.1:9067');
      expect(defaultEndpoint.presetId, 'default-regtest');
      expect(
        findRpcEndpointPresetByUrl(
          'http://127.0.0.1:9067',
          networkName: 'regtest',
        )?.id,
        'default-regtest',
      );
    });

    test('uses Stardust US as the mainnet default endpoint', () {
      final defaultEndpoint = defaultRpcEndpointConfig('main');

      expect(defaultEndpoint.networkName, 'main');
      expect(
        defaultEndpoint.lightwalletdUrl,
        'https://us.zec.stardust.rest:443',
      );
      expect(defaultEndpoint.presetId, kDefaultRpcEndpointPresetId);
    });

    test('resolves stored default preset to the current default URL', () {
      final config = resolveStoredRpcEndpointConfig(
        networkName: 'main',
        storedUrl: 'https://zec.rocks:443',
        storedPresetId: kDefaultRpcEndpointPresetId,
      );

      expect(config.lightwalletdUrl, 'https://us.zec.stardust.rest:443');
      expect(config.presetId, kDefaultRpcEndpointPresetId);
    });

    test('resolves stored non-default presets by preset id', () {
      final config = resolveStoredRpcEndpointConfig(
        networkName: 'main',
        storedUrl: 'https://us.zec.stardust.rest:443',
        storedPresetId: 'zec-rocks',
      );

      expect(config.lightwalletdUrl, 'https://zec.rocks:443');
      expect(config.presetId, 'zec-rocks');
    });

    test('keeps stored custom endpoint URLs literal', () {
      final config = resolveStoredRpcEndpointConfig(
        networkName: 'main',
        storedUrl: 'https://example.com:443',
        storedPresetId: kCustomRpcEndpointPresetId,
      );

      expect(config.lightwalletdUrl, 'https://example.com:443');
      expect(config.presetId, kCustomRpcEndpointPresetId);
    });
  });

  group('RpcEndpointConfig', () {
    test(
      'derives the effective preset from the URL before stored preset id',
      () {
        final defaultEndpoint = defaultRpcEndpointConfig('main');
        final config = RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: defaultEndpoint.lightwalletdUrl,
          presetId: kCustomRpcEndpointPresetId,
        );

        expect(config.effectivePresetId, defaultEndpoint.presetId);
      },
    );
  });

  group('fallbackRpcEndpointCandidatesFor', () {
    test('uses zec.rocks first when the mainnet default is primary', () {
      final candidates = fallbackRpcEndpointCandidatesFor(
        defaultRpcEndpointConfig('main'),
      );

      expect(candidates.first.presetId, kMainnetFallbackRpcEndpointPresetId);
      expect(candidates.first.lightwalletdUrl, 'https://zec.rocks:443');
    });

    test('does not fallback from a custom mainnet endpoint', () {
      final candidates = fallbackRpcEndpointCandidatesFor(
        const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://custom.example:443',
          presetId: kCustomRpcEndpointPresetId,
        ),
      );

      expect(candidates, isEmpty);
      expect(
        fallbackRpcEndpointConfigFor(
          const RpcEndpointConfig(
            networkName: 'main',
            lightwalletdUrl: 'https://custom.example:443',
            presetId: kCustomRpcEndpointPresetId,
          ),
        ),
        isNull,
      );
    });

    test('does not fallback from a custom regtest endpoint', () {
      final candidates = fallbackRpcEndpointCandidatesFor(
        const RpcEndpointConfig(
          networkName: 'regtest',
          lightwalletdUrl: 'http://127.0.0.1:19067',
          presetId: kCustomRpcEndpointPresetId,
        ),
      );

      expect(candidates, isEmpty);
    });

    test('respects custom intent even when the URL matches a preset', () {
      final candidates = fallbackRpcEndpointCandidatesFor(
        RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: defaultRpcEndpointConfig('main').lightwalletdUrl,
          presetId: kCustomRpcEndpointPresetId,
        ),
      );

      expect(candidates, isEmpty);
    });

    test('removes the selected preset and starts from the order beginning', () {
      final candidates = fallbackRpcEndpointCandidatesFor(
        const RpcEndpointConfig(
          networkName: 'main',
          lightwalletdUrl: 'https://eu.zec.rocks:443',
          presetId: 'eu-zec-rocks',
        ),
      );

      expect(candidates.take(4).map((candidate) => candidate.presetId), [
        kDefaultRpcEndpointPresetId,
        kMainnetFallbackRpcEndpointPresetId,
        'na-zec-rocks',
        'sa-zec-rocks',
      ]);
      expect(
        candidates.map((candidate) => candidate.presetId),
        isNot(contains('eu-zec-rocks')),
      );
    });

    test('uses local regtest default for the unavailable regtest preset', () {
      final candidates = fallbackRpcEndpointCandidatesFor(
        const RpcEndpointConfig(
          networkName: 'regtest',
          lightwalletdUrl: 'http://127.0.0.1:19067',
          presetId: kRegtestUnavailableRpcEndpointPresetId,
        ),
      );

      expect(candidates.single.presetId, 'default-regtest');
      expect(candidates.single.lightwalletdUrl, 'http://127.0.0.1:9067');
    });
  });

  group('rpcEndpointHostPort', () {
    test('keeps IPv6 brackets so custom endpoint fields can round-trip', () {
      expect(rpcEndpointHostPort('https://[::1]:9067'), '[::1]:9067');
    });
  });

  group('rpcEndpointInputText', () {
    test('preserves local http schemes for custom endpoint editing', () {
      expect(
        rpcEndpointInputText('http://127.0.0.1:9067'),
        'http://127.0.0.1:9067',
      );
    });

    test('keeps https endpoints compact for custom endpoint editing', () {
      expect(rpcEndpointInputText('https://zec.rocks:443'), 'zec.rocks:443');
    });
  });
}
