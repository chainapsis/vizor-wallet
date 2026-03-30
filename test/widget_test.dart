import 'package:flutter_test/flutter_test.dart';

import 'package:zcash_wallet/src/rust/api/wallet.dart';

void main() {
  test('WalletCreationResult equality', () {
    const a = WalletCreationResult(mnemonic: 'test', unifiedAddress: 'u1abc');
    const b = WalletCreationResult(mnemonic: 'test', unifiedAddress: 'u1abc');
    expect(a, equals(b));
  });

  test('WalletImportResult equality', () {
    const a = WalletImportResult(unifiedAddress: 'u1abc');
    const b = WalletImportResult(unifiedAddress: 'u1abc');
    expect(a, equals(b));
  });
}
