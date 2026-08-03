import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';

void main() {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  test('keeps legacy mnemonic storage unchanged without a passphrase', () {
    const secret = SoftwareWalletSecret(mnemonic: mnemonic);

    expect(secret.encodeForStorage(), mnemonic);
    expect(SoftwareWalletSecret.decode(mnemonic).mnemonic, mnemonic);
    expect(SoftwareWalletSecret.decode(mnemonic).bip39Passphrase, isEmpty);
  });

  test('round-trips a passphrase without trimming or changing case', () {
    const passphrase = '  My TREZOR phrase  ';
    const secret = SoftwareWalletSecret(
      mnemonic: mnemonic,
      bip39Passphrase: passphrase,
    );

    final decoded = SoftwareWalletSecret.decode(secret.encodeForStorage());

    expect(decoded.mnemonic, mnemonic);
    expect(decoded.bip39Passphrase, passphrase);
  });

  test(
    'rejects malformed envelope JSON instead of treating it as mnemonic',
    () {
      expect(
        () => SoftwareWalletSecret.decode('{"version":1'),
        throwsA(isA<SoftwareWalletSecretFormatException>()),
      );
      expect(
        () =>
            SoftwareWalletSecret.decode('{"version":1,"mnemonic":"$mnemonic"}'),
        throwsA(isA<SoftwareWalletSecretFormatException>()),
      );
    },
  );

  test('rejects unsupported envelope versions', () {
    expect(
      () => SoftwareWalletSecret.decode(
        '{"version":2,"mnemonic":"$mnemonic",'
        '"bip39Passphrase":"secret"}',
      ),
      throwsA(isA<SoftwareWalletSecretFormatException>()),
    );
  });
}
