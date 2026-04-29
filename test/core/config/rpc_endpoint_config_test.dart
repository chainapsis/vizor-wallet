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

    test('preserves bracketed IPv6 host formatting', () {
      expect(
        normalizeRpcEndpointUrl('https://[::1]:9067'),
        'https://[::1]:9067',
      );
    });
  });

  group('preset lookup', () {
    test('matches normalized URLs within the requested network', () {
      final preset = findRpcEndpointPresetByUrl(
        'zec.rocks',
        networkName: 'main',
      );

      expect(preset?.id, kDefaultRpcEndpointPresetId);
    });

    test('does not cross-match testnet URLs when mainnet is requested', () {
      final preset = findRpcEndpointPresetByUrl(
        'testnet.zec.rocks:443',
        networkName: 'main',
      );

      expect(preset, isNull);
    });
  });

  group('RpcEndpointConfig', () {
    test('derives the effective preset from the URL before stored preset id', () {
      final defaultEndpoint = defaultRpcEndpointConfig('main');
      final config = RpcEndpointConfig(
        networkName: 'main',
        lightwalletdUrl: defaultEndpoint.lightwalletdUrl,
        presetId: kCustomRpcEndpointPresetId,
      );

      expect(config.effectivePresetId, defaultEndpoint.presetId);
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
