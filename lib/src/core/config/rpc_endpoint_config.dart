import 'package:flutter/foundation.dart' show kDebugMode;

import 'network_config.dart';
export 'network_config.dart';

const kDefaultRpcEndpointPresetId = 'default-mainnet';
const kCustomRpcEndpointPresetId = 'custom';
const kIronwoodMasqueradeRpcEndpointPresetId = 'ironwood-masquerade';
const kZcashDefaultRpcEndpointPresetEnvKey =
    'ZCASH_DEFAULT_RPC_ENDPOINT_PRESET';
const kZcashDefaultRpcEndpointPresetIdRaw = String.fromEnvironment(
  kZcashDefaultRpcEndpointPresetEnvKey,
);
const kZcashEnableLocalIronwoodTestnetEnvKey =
    'ZCASH_ENABLE_LOCAL_IRONWOOD_TESTNET';
const kZcashEnableLocalIronwoodTestnet = bool.fromEnvironment(
  kZcashEnableLocalIronwoodTestnetEnvKey,
);
const kLocalIronwoodTestnetRpcEndpointPresetId = 'local-ironwood-testnet';
const kLocalIronwoodTestnetWalletNetworkName = 'local_ironwood_testnet';
const kRegtestSlowRpcEndpointPresetId = 'slow-regtest';
const kRegtestUnavailableRpcEndpointPresetId = 'unavailable-regtest';

class RpcEndpointConfig {
  const RpcEndpointConfig({
    required this.networkName,
    required this.lightwalletdUrl,
    this.presetId,
    String? walletNetworkName,
  }) : _walletNetworkName = walletNetworkName;

  final String networkName;
  final String lightwalletdUrl;
  final String? presetId;
  final String? _walletNetworkName;

  ZcashNetwork get network => zcashNetworkFromName(networkName);

  String get walletNetworkName =>
      _walletNetworkName ?? endpointWalletNetworkName;

  String get endpointWalletNetworkName => inferWalletNetworkName(
    networkName: networkName,
    lightwalletdUrl: lightwalletdUrl,
    presetId: presetId,
  );

  String get normalizedLightwalletdUrl =>
      normalizeRpcEndpointUrl(lightwalletdUrl, allowDefaultPort: true);

  String get hostPort => rpcEndpointHostPort(lightwalletdUrl);

  String get effectivePresetId =>
      explicitRpcEndpointPresetFor(this)?.id ?? kCustomRpcEndpointPresetId;

  RpcEndpointConfig copyWith({
    String? networkName,
    String? lightwalletdUrl,
    String? presetId,
    String? walletNetworkName,
  }) {
    return RpcEndpointConfig(
      networkName: networkName ?? this.networkName,
      lightwalletdUrl: lightwalletdUrl ?? this.lightwalletdUrl,
      presetId: presetId ?? this.presetId,
      walletNetworkName: walletNetworkName ?? this.walletNetworkName,
    );
  }
}

String inferWalletNetworkName({
  required String networkName,
  required String lightwalletdUrl,
  String? presetId,
}) {
  final network = zcashNetworkFromName(networkName);
  if (network == ZcashNetwork.testnet &&
      (presetId == kLocalIronwoodTestnetRpcEndpointPresetId ||
          normalizeRpcEndpointUrl(lightwalletdUrl, allowDefaultPort: true) ==
              normalizeRpcEndpointUrl(
                kLocalIronwoodTestnetRpcEndpointPreset.url,
                allowDefaultPort: true,
              ))) {
    return kLocalIronwoodTestnetWalletNetworkName;
  }
  return network.name;
}

String? normalizeWalletNetworkName(String? walletNetworkName) {
  final value = walletNetworkName?.trim();
  return switch (value) {
    'main' => 'main',
    'test' => 'test',
    kLocalIronwoodTestnetWalletNetworkName =>
      kLocalIronwoodTestnetWalletNetworkName,
    'regtest' => 'regtest',
    _ => null,
  };
}

String publicNetworkNameForWalletNetworkName(String walletNetworkName) {
  return walletNetworkName == kLocalIronwoodTestnetWalletNetworkName
      ? ZcashNetwork.testnet.name
      : zcashNetworkFromName(walletNetworkName).name;
}

RpcEndpointConfig defaultRpcEndpointConfigForWalletNetwork(
  String walletNetworkName,
) {
  final normalized =
      normalizeWalletNetworkName(walletNetworkName) ?? kZcashDefaultNetworkName;
  final publicNetwork = publicNetworkNameForWalletNetworkName(normalized);
  final endpoint = defaultRpcEndpointConfig(
    publicNetwork,
    defaultPresetId: normalized == kLocalIronwoodTestnetWalletNetworkName
        ? kLocalIronwoodTestnetRpcEndpointPresetId
        : '',
    includeLocalIronwoodTestnet:
        normalized == kLocalIronwoodTestnetWalletNetworkName ||
        kZcashEnableLocalIronwoodTestnet,
  );
  return endpoint.copyWith(walletNetworkName: normalized);
}

Map<String, String> nativeRpcEndpointPayload(
  RpcEndpointConfig endpoint, {
  required String walletNetworkName,
}) {
  return {
    'lightwalletdUrl': endpoint.normalizedLightwalletdUrl,
    'network': walletNetworkName,
    'presetId': endpoint.effectivePresetId,
  };
}

class RpcEndpointPreset {
  const RpcEndpointPreset({
    required this.id,
    required this.region,
    required this.label,
    required this.url,
    this.isDefault = false,
  });

  final String id;
  final String region;
  final String label;
  final String url;
  final bool isDefault;

  String get hostPort => rpcEndpointHostPort(url);
}

// Public lightwalletd presets. Keep the mainnet default aligned with Zodl's
// default endpoint while preserving zec.rocks as a selectable fallback.
const kIronwoodMasqueradeRpcEndpointPreset = RpcEndpointPreset(
  id: kIronwoodMasqueradeRpcEndpointPresetId,
  region: 'Ironwood',
  label: 'Ironwood Masquerade',
  url: 'https://lwd.157.245.208.35.sslip.io:443',
  isDefault: true,
);

final kMainnetRpcEndpointPresets = List<RpcEndpointPreset>.unmodifiable([
  RpcEndpointPreset(
    id: kDefaultRpcEndpointPresetId,
    region: 'Default',
    label: 'Stardust US',
    url: ZcashNetwork.mainnet.lightwalletdUrl,
    isDefault: true,
  ),
  const RpcEndpointPreset(
    id: 'eu-zec-stardust',
    region: 'Europe',
    label: 'Stardust Europe',
    url: 'https://eu.zec.stardust.rest:443',
  ),
  const RpcEndpointPreset(
    id: 'eu2-zec-stardust',
    region: 'Europe',
    label: 'Stardust Europe 2',
    url: 'https://eu2.zec.stardust.rest:443',
  ),
  const RpcEndpointPreset(
    id: 'jp-zec-stardust',
    region: 'Asia Pacific',
    label: 'Stardust Japan',
    url: 'https://jp.zec.stardust.rest:443',
  ),
  const RpcEndpointPreset(
    id: 'zec-rocks',
    region: 'Global',
    label: 'Zec Rocks',
    url: 'https://zec.rocks:443',
  ),
  const RpcEndpointPreset(
    id: 'na-zec-rocks',
    region: 'Americas',
    label: 'Zec Rocks North America',
    url: 'https://na.zec.rocks:443',
  ),
  const RpcEndpointPreset(
    id: 'sa-zec-rocks',
    region: 'Americas',
    label: 'Zec Rocks South America',
    url: 'https://sa.zec.rocks:443',
  ),
  const RpcEndpointPreset(
    id: 'eu-zec-rocks',
    region: 'Europe',
    label: 'Zec Rocks Europe',
    url: 'https://eu.zec.rocks:443',
  ),
  const RpcEndpointPreset(
    id: 'ap-zec-rocks',
    region: 'Asia Pacific',
    label: 'Zec Rocks Asia Pacific',
    url: 'https://ap.zec.rocks:443',
  ),
  const RpcEndpointPreset(
    id: 'z3-deepikaw',
    region: 'Community',
    label: 'Deepikaw Z3',
    url: 'https://z3.deepikaw.xyz:443',
  ),
  const RpcEndpointPreset(
    id: 'zprivacy',
    region: 'Community',
    label: 'ZPrivacy',
    url: 'https://zprivacy.online:443',
  ),
  const RpcEndpointPreset(
    id: 'zcash-explorer',
    region: 'Community',
    label: 'Zcash Explorer',
    url: 'https://lwd.zcashexplorer.app:9067',
  ),
]);

const kLocalIronwoodTestnetRpcEndpointPreset = RpcEndpointPreset(
  id: kLocalIronwoodTestnetRpcEndpointPresetId,
  region: 'Testnet',
  label: 'Local Ironwood',
  url: 'https://174-138-65-204.sslip.io:9067',
);

final kTestnetRpcEndpointPresets = List<RpcEndpointPreset>.unmodifiable([
  const RpcEndpointPreset(
    id: 'default-testnet',
    region: 'Testnet',
    label: 'Zec Rocks Testnet',
    url: 'https://testnet.zec.rocks:443',
    isDefault: true,
  ),
  const RpcEndpointPreset(
    id: 'mysideoftheweb-testnet',
    region: 'Community',
    label: 'My Side of the Web Testnet',
    url: 'https://zcash.mysideoftheweb.com:19067',
  ),
]);

final kRegtestRpcEndpointPresets = List<RpcEndpointPreset>.unmodifiable([
  RpcEndpointPreset(
    id: 'default-regtest',
    region: 'Regtest',
    label: 'Local Regtest',
    url: ZcashNetwork.regtest.lightwalletdUrl,
    isDefault: true,
  ),
  const RpcEndpointPreset(
    id: kRegtestSlowRpcEndpointPresetId,
    region: 'Regtest',
    label: 'Slow Regtest',
    url: 'http://127.0.0.1:19068',
  ),
  const RpcEndpointPreset(
    id: kRegtestUnavailableRpcEndpointPresetId,
    region: 'Regtest',
    label: 'Unavailable Regtest',
    url: 'http://127.0.0.1:19067',
  ),
]);

List<RpcEndpointPreset> rpcEndpointPresetsForNetwork(
  String networkName, {
  bool includeLocalIronwoodTestnet = kZcashEnableLocalIronwoodTestnet,
}) {
  final network = zcashNetworkFromName(networkName);
  return switch (network) {
    ZcashNetwork.mainnet =>
      kZcashIronwoodMasquerade
          ? List<RpcEndpointPreset>.unmodifiable([
              kIronwoodMasqueradeRpcEndpointPreset,
              ...kMainnetRpcEndpointPresets,
            ])
          : kMainnetRpcEndpointPresets,
    ZcashNetwork.testnet =>
      includeLocalIronwoodTestnet
          ? List<RpcEndpointPreset>.unmodifiable([
              kLocalIronwoodTestnetRpcEndpointPreset,
              ...kTestnetRpcEndpointPresets,
            ])
          : kTestnetRpcEndpointPresets,
    ZcashNetwork.regtest => kRegtestRpcEndpointPresets,
  };
}

RpcEndpointConfig defaultRpcEndpointConfig(
  String networkName, {
  String defaultPresetId = kZcashDefaultRpcEndpointPresetIdRaw,
  bool includeLocalIronwoodTestnet = kZcashEnableLocalIronwoodTestnet,
}) {
  final network = zcashNetworkFromName(networkName);
  final presets = rpcEndpointPresetsForNetwork(
    network.name,
    includeLocalIronwoodTestnet: includeLocalIronwoodTestnet,
  );
  final requestedPresetId = defaultPresetId.trim();
  final requestedPreset = requestedPresetId.isEmpty
      ? null
      : findRpcEndpointPresetById(
          network.name,
          requestedPresetId,
          includeLocalIronwoodTestnet: includeLocalIronwoodTestnet,
        );
  final preset =
      requestedPreset ??
      presets.firstWhere(
        (preset) => preset.isDefault,
        orElse: () => presets.first,
      );
  return RpcEndpointConfig(
    networkName: network.name,
    lightwalletdUrl: preset.url,
    presetId: preset.id,
  );
}

bool isCustomRpcEndpointConfig(RpcEndpointConfig config) {
  return config.presetId == kCustomRpcEndpointPresetId;
}

RpcEndpointPreset? explicitRpcEndpointPresetFor(RpcEndpointConfig config) {
  final presetId = config.presetId?.trim();
  if (presetId == null ||
      presetId.isEmpty ||
      presetId == kCustomRpcEndpointPresetId) {
    return null;
  }

  return findRpcEndpointPresetById(config.networkName, presetId);
}

List<RpcEndpointConfig> fallbackRpcEndpointCandidatesFor(
  RpcEndpointConfig primary, {
  bool includeLocalIronwoodTestnet = kZcashEnableLocalIronwoodTestnet,
}) {
  if (isLocalIronwoodTestnetEndpoint(primary)) return const [];

  final primaryPreset = _selectedFallbackPrimaryPreset(primary);
  if (primaryPreset == null) return const [];

  final primaryNormalized = primary.normalizedLightwalletdUrl;
  final seenUrls = <String>{};
  final candidates = <RpcEndpointConfig>[];

  for (final preset in rpcEndpointPresetsForNetwork(
    primary.networkName,
    includeLocalIronwoodTestnet: includeLocalIronwoodTestnet,
  )) {
    final normalized = normalizeRpcEndpointUrl(
      preset.url,
      allowDefaultPort: true,
    );
    if (preset.id == primaryPreset.id || normalized == primaryNormalized) {
      continue;
    }
    if (!seenUrls.add(normalized)) continue;

    candidates.add(
      RpcEndpointConfig(
        networkName: primary.networkName,
        lightwalletdUrl: preset.url,
        presetId: preset.id,
        walletNetworkName: primary.walletNetworkName,
      ),
    );
  }

  return List.unmodifiable(
    candidates.where(
      (candidate) =>
          candidate.endpointWalletNetworkName == primary.walletNetworkName,
    ),
  );
}

RpcEndpointConfig? fallbackRpcEndpointConfigFor(RpcEndpointConfig primary) {
  final candidates = fallbackRpcEndpointCandidatesFor(primary);
  return candidates.isEmpty ? null : candidates.first;
}

RpcEndpointPreset? _selectedFallbackPrimaryPreset(RpcEndpointConfig primary) {
  return explicitRpcEndpointPresetFor(primary);
}

RpcEndpointConfig resolveStoredRpcEndpointConfig({
  required String networkName,
  required String? storedUrl,
  required String? storedPresetId,
  String? storedWalletNetworkName,
}) {
  final network = zcashNetworkFromName(networkName);
  final walletNetworkName = normalizeWalletNetworkName(storedWalletNetworkName);
  final presetId = storedPresetId?.trim();
  RpcEndpointConfig? candidate;
  if (presetId != null &&
      presetId.isNotEmpty &&
      presetId != kCustomRpcEndpointPresetId) {
    final preset = findRpcEndpointPresetById(network.name, presetId);
    if (preset != null) {
      candidate = RpcEndpointConfig(
        networkName: network.name,
        lightwalletdUrl: preset.url,
        presetId: preset.id,
      );
    }
  }

  if (candidate == null) {
    final url = storedUrl?.trim();
    if (url == null || url.isEmpty) {
      candidate = defaultRpcEndpointConfig(network.name);
    } else {
      candidate = RpcEndpointConfig(
        networkName: network.name,
        lightwalletdUrl: normalizeRpcEndpointUrl(url, allowDefaultPort: true),
        presetId: kCustomRpcEndpointPresetId,
      );
    }
  }

  if (walletNetworkName == null) return candidate;
  if (candidate.walletNetworkName == walletNetworkName) {
    return candidate.copyWith(walletNetworkName: walletNetworkName);
  }
  return defaultRpcEndpointConfigForWalletNetwork(walletNetworkName);
}

RpcEndpointPreset? findRpcEndpointPresetById(
  String networkName,
  String presetId, {
  bool includeLocalIronwoodTestnet = kZcashEnableLocalIronwoodTestnet,
}) {
  for (final preset in rpcEndpointPresetsForNetwork(
    networkName,
    includeLocalIronwoodTestnet: includeLocalIronwoodTestnet,
  )) {
    if (preset.id == presetId) return preset;
  }
  return null;
}

RpcEndpointPreset? findRpcEndpointPresetByUrl(
  String url, {
  String? networkName,
  bool includeLocalIronwoodTestnet = kZcashEnableLocalIronwoodTestnet,
}) {
  final normalized = normalizeRpcEndpointUrl(url, allowDefaultPort: true);
  final presets = networkName == null
      ? [
          ...rpcEndpointPresetsForNetwork(ZcashNetwork.mainnet.name),
          ...rpcEndpointPresetsForNetwork(
            ZcashNetwork.testnet.name,
            includeLocalIronwoodTestnet: includeLocalIronwoodTestnet,
          ),
        ]
      : rpcEndpointPresetsForNetwork(
          networkName,
          includeLocalIronwoodTestnet: includeLocalIronwoodTestnet,
        );
  for (final preset in presets) {
    if (normalizeRpcEndpointUrl(preset.url, allowDefaultPort: true) ==
        normalized) {
      return preset;
    }
  }
  return null;
}

bool isLocalIronwoodTestnetEndpoint(RpcEndpointConfig config) {
  // Mainnet-masquerade: this build runs as `main` (so it derives mainnet 133'/u1 keys for a
  // normal-mode Keystone) but always points at the private Ironwood test chain. Treat every
  // endpoint as the Ironwood testnet so the migration flow + Ironwood balances surface, while
  // walletNetworkName stays "main" for derivation/keychain. See kZcashIronwoodMasquerade.
  if (kZcashIronwoodMasquerade) return true;
  if (config.network != ZcashNetwork.testnet) return false;
  if (config.presetId == kLocalIronwoodTestnetRpcEndpointPresetId) {
    return true;
  }

  return config.normalizedLightwalletdUrl ==
      normalizeRpcEndpointUrl(
        kLocalIronwoodTestnetRpcEndpointPreset.url,
        allowDefaultPort: true,
      );
}

String normalizeRpcEndpointUrl(
  String input, {
  bool allowDefaultPort = false,
  bool allowLocalHttp = kDebugMode,
}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Enter an endpoint.');
  }
  if (trimmed.contains(RegExp(r'\s'))) {
    throw const FormatException('Endpoint cannot contain spaces.');
  }

  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) {
    throw const FormatException('Enter a valid hostname and port.');
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw const FormatException('Use an https:// endpoint.');
  }
  if (uri.scheme == 'http' && !(allowLocalHttp && _isLocalhost(uri.host))) {
    throw const FormatException('Use an https:// endpoint.');
  }
  final hasExplicitPort = _hasExplicitPort(candidate);
  if (!hasExplicitPort && !allowDefaultPort) {
    throw const FormatException(
      'Include a valid port, for example us.zec.stardust.rest:443.',
    );
  }
  final port = hasExplicitPort ? uri.port : _defaultPortForScheme(uri.scheme);
  if (port <= 0 || port > 65535) {
    throw const FormatException(
      'Include a valid port, for example us.zec.stardust.rest:443.',
    );
  }

  return '${uri.scheme}://${_formatRpcHost(uri.host)}:$port';
}

bool _isLocalhost(String host) {
  final lower = host.toLowerCase();
  return lower == 'localhost' ||
      lower == '::1' ||
      lower == '10.0.2.2' ||
      lower.startsWith('127.');
}

bool _hasExplicitPort(String url) {
  final schemeIndex = url.indexOf('://');
  if (schemeIndex < 0) return false;

  final afterScheme = url.substring(schemeIndex + 3);
  final authorityEnd = afterScheme.indexOf(RegExp(r'[/#?]'));
  final authority = authorityEnd < 0
      ? afterScheme
      : afterScheme.substring(0, authorityEnd);
  final hostPort = authority.contains('@')
      ? authority.substring(authority.lastIndexOf('@') + 1)
      : authority;

  if (hostPort.startsWith('[')) {
    final closeBracket = hostPort.indexOf(']');
    return closeBracket >= 0 &&
        closeBracket + 1 < hostPort.length &&
        hostPort[closeBracket + 1] == ':';
  }

  return hostPort.lastIndexOf(':') > 0;
}

String rpcEndpointHostPort(String url) {
  final uri = Uri.parse(normalizeRpcEndpointUrl(url, allowDefaultPort: true));
  return '${_formatRpcHost(uri.host)}:${uri.port}';
}

String rpcEndpointInputText(String url) {
  final normalized = normalizeRpcEndpointUrl(url, allowDefaultPort: true);
  final uri = Uri.parse(normalized);
  if (uri.scheme == 'https') {
    return rpcEndpointHostPort(normalized);
  }
  return normalized;
}

int _defaultPortForScheme(String scheme) {
  return switch (scheme) {
    'https' => 443,
    'http' => 80,
    _ => 0,
  };
}

String _formatRpcHost(String host) {
  if (host.contains(':') && !host.startsWith('[')) {
    return '[$host]';
  }
  return host;
}
