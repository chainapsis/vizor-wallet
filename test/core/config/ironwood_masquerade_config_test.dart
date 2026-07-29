import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';

void main() {
  test(
    'masquerade build keeps mainnet identity with isolated storage and endpoint',
    () {
      expect(kZcashIronwoodMasquerade, isTrue);
      expect(kZcashDefaultNetworkName, 'main');
      expect(
        secureStoreServiceForNetwork(kZcashDefaultNetworkName),
        'com.keplr.vizor.ironwood.secure_store',
      );

      final endpoint = defaultRpcEndpointConfig(kZcashDefaultNetworkName);
      expect(endpoint.networkName, 'main');
      expect(endpoint.presetId, kIronwoodMasqueradeRpcEndpointPresetId);
      expect(
        endpoint.normalizedLightwalletdUrl,
        'https://lwd.157.245.208.35.sslip.io:443',
      );

      final presets = rpcEndpointPresetsForNetwork('main');
      expect(presets, [kIronwoodMasqueradeRpcEndpointPreset]);
      expect(fallbackRpcEndpointCandidatesFor(endpoint), isEmpty);
      expect(isRpcEndpointAllowedForBuild(endpoint.lightwalletdUrl), isTrue);
      expect(
        isRpcEndpointAllowedForBuild('https://us.zec.stardust.rest:443'),
        isFalse,
      );

      final restored = resolveStoredRpcEndpointConfig(
        networkName: 'main',
        storedUrl: 'https://us.zec.stardust.rest:443',
        storedPresetId: kCustomRpcEndpointPresetId,
      );
      expect(restored.presetId, kIronwoodMasqueradeRpcEndpointPresetId);
      expect(restored.lightwalletdUrl, endpoint.lightwalletdUrl);
    },
    skip: !kZcashIronwoodMasquerade
        ? 'Requires --dart-define=ZCASH_IRONWOOD_MASQUERADE=true'
        : false,
  );
}
