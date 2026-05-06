import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';

void main() {
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

  group('secureStoreServiceForNetwork', () {
    test('keeps the existing mainnet service name', () {
      expect(
        secureStoreServiceForNetwork('main'),
        'com.keplr.vizor.secure_store',
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
        'com.keplr.vizor.secure_store',
      );
    });
  });
}
