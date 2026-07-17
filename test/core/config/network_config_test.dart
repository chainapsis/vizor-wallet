import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';

void main() {
  test('regtest Ironwood activation is opt-in by default', () {
    expect(kZcashRegtestIronwoodActivationHeight, 0xFFFFFFFF);
  });

  group('normalizeZcashNetworkName', () {
    test('accepts supported network names', () {
      expect(normalizeZcashNetworkName('main'), 'main');
      expect(normalizeZcashNetworkName('test'), 'test');
      expect(normalizeZcashNetworkName('regtest'), 'regtest');
    });

    test('trims and falls back to main for unknown values', () {
      expect(normalizeZcashNetworkName(' test '), 'test');
      expect(normalizeZcashNetworkName(''), 'main');
      expect(normalizeZcashNetworkName('invalid'), 'main');
    });
  });

  group('resolveStoredOrDefaultZcashNetworkName', () {
    test('uses the build-time default for missing stored values', () {
      expect(
        resolveStoredOrDefaultZcashNetworkName(null),
        kZcashDefaultNetworkName,
      );
      expect(
        resolveStoredOrDefaultZcashNetworkName(''),
        kZcashDefaultNetworkName,
      );
    });
  });

  group('currencyTicker', () {
    test('uses ZEC for mainnet and TAZ for test networks', () {
      expect(ZcashNetwork.mainnet.currencyTicker, 'ZEC');
      expect(ZcashNetwork.testnet.currencyTicker, 'TAZ');
      expect(ZcashNetwork.regtest.currencyTicker, 'TAZ');
    });

    test('derives the default ticker from the build-time default network', () {
      expect(
        kZcashDefaultCurrencyTicker,
        zcashNetworkFromName(kZcashDefaultNetworkName).currencyTicker,
      );
    });
  });

  group('secureStoreServiceForNetwork', () {
    test('keeps the existing mainnet service name', () {
      expect(
        secureStoreServiceForNetwork('main'),
        kZcashIronwoodMasquerade
            ? 'com.keplr.vizor.ironwood.secure_store'
            : 'com.keplr.vizor.secure_store',
      );
    });

    test('adds the network name for non-main networks', () {
      expect(
        secureStoreServiceForNetwork('test'),
        'com.keplr.vizor.test.secure_store',
      );
      expect(
        secureStoreServiceForNetwork('regtest'),
        'com.keplr.vizor.regtest.secure_store',
      );
    });

    test('normalizes unknown values before choosing the service', () {
      expect(
        secureStoreServiceForNetwork('unknown'),
        kZcashIronwoodMasquerade
            ? 'com.keplr.vizor.ironwood.secure_store'
            : 'com.keplr.vizor.secure_store',
      );
    });
  });
}
