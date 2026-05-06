import 'package:flutter/foundation.dart' show kDebugMode;

import 'network_config.dart';
export 'network_config.dart';

const kDefaultRpcEndpointPresetId = 'default-mainnet';
const kCustomRpcEndpointPresetId = 'custom';

class RpcEndpointConfig {
  const RpcEndpointConfig({
    required this.networkName,
    required this.lightwalletdUrl,
    this.presetId,
  });

  final String networkName;
  final String lightwalletdUrl;
  final String? presetId;

  ZcashNetwork get network => zcashNetworkFromName(networkName);

  String get normalizedLightwalletdUrl =>
      normalizeRpcEndpointUrl(lightwalletdUrl, allowDefaultPort: true);

  String get hostPort => rpcEndpointHostPort(lightwalletdUrl);

  String get effectivePresetId =>
      findRpcEndpointPresetByUrl(
        normalizedLightwalletdUrl,
        networkName: networkName,
      )?.id ??
      presetId ??
      kCustomRpcEndpointPresetId;

  RpcEndpointConfig copyWith({
    String? networkName,
    String? lightwalletdUrl,
    String? presetId,
  }) {
    return RpcEndpointConfig(
      networkName: networkName ?? this.networkName,
      lightwalletdUrl: lightwalletdUrl ?? this.lightwalletdUrl,
      presetId: presetId ?? this.presetId,
    );
  }
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

// Additional regional lightwalletd presets while keeping this app's existing
// zec.rocks default unchanged.
final kMainnetRpcEndpointPresets = List<RpcEndpointPreset>.unmodifiable([
  RpcEndpointPreset(
    id: kDefaultRpcEndpointPresetId,
    region: 'Default',
    label: 'Zec Rocks',
    url: ZcashNetwork.mainnet.lightwalletdUrl,
    isDefault: true,
  ),
  const RpcEndpointPreset(
    id: 'us-zec-stardust',
    region: 'Americas',
    label: 'Stardust US',
    url: 'https://us.zec.stardust.rest:443',
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
]);

final kTestnetRpcEndpointPresets = List<RpcEndpointPreset>.unmodifiable([
  const RpcEndpointPreset(
    id: 'default-testnet',
    region: 'Testnet',
    label: 'Zec Rocks Testnet',
    url: 'https://testnet.zec.rocks:443',
    isDefault: true,
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
]);

List<RpcEndpointPreset> rpcEndpointPresetsForNetwork(String networkName) {
  final network = zcashNetworkFromName(networkName);
  return switch (network) {
    ZcashNetwork.mainnet => kMainnetRpcEndpointPresets,
    ZcashNetwork.testnet => kTestnetRpcEndpointPresets,
    ZcashNetwork.regtest => kRegtestRpcEndpointPresets,
  };
}

RpcEndpointConfig defaultRpcEndpointConfig(String networkName) {
  final network = zcashNetworkFromName(networkName);
  final presets = rpcEndpointPresetsForNetwork(network.name);
  final preset = presets.firstWhere(
    (preset) => preset.isDefault,
    orElse: () => presets.first,
  );
  return RpcEndpointConfig(
    networkName: network.name,
    lightwalletdUrl: preset.url,
    presetId: preset.id,
  );
}

RpcEndpointPreset? findRpcEndpointPresetById(
  String networkName,
  String presetId,
) {
  for (final preset in rpcEndpointPresetsForNetwork(networkName)) {
    if (preset.id == presetId) return preset;
  }
  return null;
}

RpcEndpointPreset? findRpcEndpointPresetByUrl(
  String url, {
  String? networkName,
}) {
  final normalized = normalizeRpcEndpointUrl(url, allowDefaultPort: true);
  final presets = networkName == null
      ? [...kMainnetRpcEndpointPresets, ...kTestnetRpcEndpointPresets]
      : rpcEndpointPresetsForNetwork(networkName);
  for (final preset in presets) {
    if (normalizeRpcEndpointUrl(preset.url, allowDefaultPort: true) ==
        normalized) {
      return preset;
    }
  }
  return null;
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
      'Include a valid port, for example zec.rocks:443.',
    );
  }
  final port = hasExplicitPort ? uri.port : _defaultPortForScheme(uri.scheme);
  if (port <= 0 || port > 65535) {
    throw const FormatException(
      'Include a valid port, for example zec.rocks:443.',
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
