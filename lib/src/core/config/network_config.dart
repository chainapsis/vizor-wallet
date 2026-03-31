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

  String get lightwalletdHost => switch (this) {
        mainnet => 'zec.rocks',
        testnet => 'lightwalletd.testnet.electriccoin.co',
      };

  int get lightwalletdPort => switch (this) {
        mainnet => 443,
        testnet => 9067,
      };

  String get lightwalletdUrl =>
      'https://$lightwalletdHost:$lightwalletdPort';
}
