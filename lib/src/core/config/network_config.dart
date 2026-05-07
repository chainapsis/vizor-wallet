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

final String kZcashDefaultNetworkName = normalizeZcashNetworkName(
  kZcashDefaultNetworkRaw,
);

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
  return network == 'main'
      ? 'com.keplr.vizor.secure_store'
      : 'com.keplr.vizor.$network.secure_store';
}
