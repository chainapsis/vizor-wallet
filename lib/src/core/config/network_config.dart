enum ZcashNetwork {
  mainnet,
  testnet,
  regtest;

  String get name => switch (this) {
    mainnet => 'main',
    testnet => 'test',
    regtest => 'regtest',
  };

  int get coinType => switch (this) {
    mainnet => 133,
    testnet => 1,
    regtest => 1,
  };

  String get tAddrPrefix => switch (this) {
    mainnet => 't1',
    testnet => 'tm',
    regtest => 'tm',
  };

  String get saplingPrefix => switch (this) {
    mainnet => 'zs',
    testnet => 'ztestsapling',
    regtest => 'zregtestsapling',
  };

  String get uaPrefix => switch (this) {
    mainnet => 'u1',
    testnet => 'utest1',
    regtest => 'uregtest1',
  };

  int get defaultPort => switch (this) {
    mainnet => 9067,
    testnet => 18232,
    regtest => 9067,
  };

  String get lightwalletdHost => switch (this) {
    mainnet => 'us.zec.stardust.rest',
    testnet => 'lightwalletd.testnet.electriccoin.co',
    regtest => '127.0.0.1',
  };

  int get lightwalletdPort => switch (this) {
    mainnet => 443,
    testnet => 9067,
    regtest => 9067,
  };

  String get currencyTicker => switch (this) {
    mainnet => 'ZEC',
    testnet => 'TAZ',
    regtest => 'TAZ',
  };

  String get lightwalletdUrl => switch (this) {
    regtest => 'http://$lightwalletdHost:$lightwalletdPort',
    _ => 'https://$lightwalletdHost:$lightwalletdPort',
  };

  int get saplingActivationHeight => switch (this) {
    mainnet => 419200,
    testnet => 280000,
    regtest => 1,
  };
}

const kZcashDefaultNetworkEnvKey = 'ZCASH_DEFAULT_NETWORK';
const kZcashDefaultNetworkRaw = String.fromEnvironment(
  kZcashDefaultNetworkEnvKey,
  defaultValue: 'main',
);

/// Ironwood mainnet-masquerade build flag. When true (set via
/// `--dart-define=ZCASH_IRONWOOD_MASQUERADE=true`), this build runs as `networkName=main` (so it
/// derives mainnet 133'/u1 keys and a normal-mode Keystone works) BUT against the private Ironwood
/// test chain that masquerades as mainnet. It isolates the keychain (see
/// [secureStoreServiceForNetwork]) and surfaces the Ironwood migration flow so this build can never
/// touch a real mainnet wallet. OFF by default — a normal build is unaffected.
const kZcashIronwoodMasqueradeEnvKey = 'ZCASH_IRONWOOD_MASQUERADE';
const kZcashIronwoodMasquerade = bool.fromEnvironment(
  kZcashIronwoodMasqueradeEnvKey,
  defaultValue: false,
);

final String kZcashDefaultNetworkName = normalizeZcashNetworkName(
  kZcashDefaultNetworkRaw,
);

final String kZcashDefaultCurrencyTicker = zcashNetworkFromName(
  kZcashDefaultNetworkName,
).currencyTicker;

String normalizeZcashNetworkName(String networkName) {
  return switch (networkName.trim()) {
    'test' => 'test',
    'regtest' => 'regtest',
    _ => 'main',
  };
}

String resolveStoredOrDefaultZcashNetworkName(String? storedNetworkName) {
  final stored = storedNetworkName?.trim();
  if (stored == null || stored.isEmpty) return kZcashDefaultNetworkName;
  return normalizeZcashNetworkName(stored);
}

ZcashNetwork zcashNetworkFromName(String networkName) {
  return switch (normalizeZcashNetworkName(networkName)) {
    'test' => ZcashNetwork.testnet,
    'regtest' => ZcashNetwork.regtest,
    _ => ZcashNetwork.mainnet,
  };
}

String secureStoreServiceForNetwork(String networkName) {
  final network = normalizeZcashNetworkName(networkName);
  // Ironwood mainnet-masquerade: a `main`-network build pointed at the Ironwood test chain must
  // NEVER share the real mainnet wallet's keychain. The keychain service is a fixed string (not
  // bundle-scoped), so isolate it here under a distinct service. The masquerade build then can't
  // read/write real mainnet secrets even though it runs as `main`.
  if (kZcashIronwoodMasquerade && network == 'main') {
    return 'com.keplr.vizor.ironwood.secure_store';
  }
  return network == 'main'
      ? 'com.keplr.vizor.secure_store'
      : 'com.keplr.vizor.$network.secure_store';
}
