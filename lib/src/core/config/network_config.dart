enum ZcashNetwork {
  mainnet,
  testnet;

  String get name => switch (this) {
        mainnet => 'main',
        testnet => 'test',
      };

  int get coinType => switch (this) {
        mainnet => 133,
        testnet => 1,
      };

  String get tAddrPrefix => switch (this) {
        mainnet => 't1',
        testnet => 'tm',
      };

  String get saplingPrefix => switch (this) {
        mainnet => 'zs',
        testnet => 'ztestsapling',
      };

  String get uaPrefix => switch (this) {
        mainnet => 'u1',
        testnet => 'utest1',
      };

  int get defaultPort => switch (this) {
        mainnet => 9067,
        testnet => 18232,
      };
}
