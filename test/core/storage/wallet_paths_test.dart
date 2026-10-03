import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';

void main() {
  tearDown(resetWalletDataDirectoryOverrideForTesting);

  group('configureWalletDataDirectoryOverride', () {
    test('parses --wallet-data-dir=<path>', () {
      configureWalletDataDirectoryOverride([
        '--wallet-data-dir=/mnt/usb/vizor-data',
      ]);

      expect(walletDataDirectoryOverrideForTesting, '/mnt/usb/vizor-data');
    });

    test('parses --wallet-data-dir <path> as two separate arguments', () {
      configureWalletDataDirectoryOverride([
        '--wallet-data-dir',
        '/mnt/usb/vizor-data',
      ]);

      expect(walletDataDirectoryOverrideForTesting, '/mnt/usb/vizor-data');
    });

    test('ignores an unrelated argument list', () {
      configureWalletDataDirectoryOverride(['zcash:t1abc...']);

      expect(walletDataDirectoryOverrideForTesting, isNull);
    });

    test('ignores an empty --wallet-data-dir value', () {
      configureWalletDataDirectoryOverride(['--wallet-data-dir=']);

      expect(walletDataDirectoryOverrideForTesting, isNull);
    });

    test('a trailing --wallet-data-dir with no value is ignored', () {
      configureWalletDataDirectoryOverride(['--wallet-data-dir']);

      expect(walletDataDirectoryOverrideForTesting, isNull);
    });

    test('an empty argument list is a no-op', () {
      configureWalletDataDirectoryOverride(const []);

      expect(walletDataDirectoryOverrideForTesting, isNull);
    });
  });
}
