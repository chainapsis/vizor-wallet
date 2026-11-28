/// Where Vizor's signed delegate list lives and, on regtest, which key signs
/// it (contracts-v1 section 12.3). The URLs come from the build, never
/// from the unsigned config extension. Mainnet and testnet pins are compiled
/// into Rust (`rust/src/api/proxy_registry.rs`).
library;

const kVizorProxyWalletListUrlEnvKey = 'VIZOR_PROXY_WALLET_LIST_URL';

/// The regtest harness's list URL. Ignored on mainnet and testnet.
const kVizorProxyWalletListUrl = String.fromEnvironment(
  kVizorProxyWalletListUrlEnvKey,
);

const kVizorProxyWalletListKeyEnvKey = 'VIZOR_PROXY_WALLET_LIST_KEY';

/// The key the regtest harness signs its test list with, as
/// `<key_id>:<base64 Ed25519 public key>`. Ignored on mainnet and testnet,
/// whose keys are compiled in.
const kVizorProxyWalletListKey = String.fromEnvironment(
  kVizorProxyWalletListKeyEnvKey,
);

/// The config repo's environment folder for [network], or null for a
/// network whose list comes from the harness.
String? _environment(String network) => switch (network) {
  'main' => 'prod',
  'test' => 'stage',
  _ => null,
};

/// Vizor's list mirrors on [network], most preferred first: the config
/// gateway, then the config repo itself. A mirror can only serve a signed
/// list, so a second origin widens availability without widening trust.
List<String> proxyWalletListUrls(
  String network, {
  String regtestUrl = kVizorProxyWalletListUrl,
}) {
  final environment = _environment(network);
  if (environment == null) {
    return network == 'regtest' && regtestUrl.isNotEmpty
        ? [regtestUrl]
        : const [];
  }
  final path = '$environment/wallets/vizor/list.json';
  return [
    'https://voting.valargroup.dev/$path',
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/main/$path',
  ];
}

/// The regtest list key from [setting] (`<key_id>:<base64>`), or null when
/// unset or malformed.
({String keyId, String publicKey})? proxyRegtestWalletListKey([
  String setting = kVizorProxyWalletListKey,
]) {
  final separator = setting.indexOf(':');
  if (separator <= 0 || separator == setting.length - 1) return null;
  return (
    keyId: setting.substring(0, separator),
    publicKey: setting.substring(separator + 1),
  );
}
