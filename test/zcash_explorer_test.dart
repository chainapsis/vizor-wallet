import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/zcash_explorer.dart';

void main() {
  test('builds mainnet transaction explorer URL from protocol-order txid', () {
    expect(
      zcashExplorerTransactionUri(
        networkName: 'main',
        txidHex:
            'd6e03b5276de779d532791a82a28da7fb6b60524bf5996f4d7629cd794682c01',
        txidOrder: ZcashExplorerTxidOrder.protocol,
      ).toString(),
      'https://mainnet.zcashexplorer.app/transactions/'
      '012c6894d79c62d7f49659bf2405b6b67fda282aa89127539d77de76523be0d6',
    );
  });

  test('builds testnet transaction explorer URL from protocol-order txid', () {
    expect(
      zcashExplorerTransactionUri(
        networkName: 'test',
        txidHex:
            '6088ad5facf418b825ab83b421af13a444173627b56d626f586976b9a9c8733b',
        txidOrder: ZcashExplorerTxidOrder.protocol,
      ).toString(),
      'https://testnet.zcashexplorer.app/transactions/'
      '3b73c8a9b97669586f626db527361744a413af21b483ab25b818f4ac5fad8860',
    );
  });

  test('builds URL for a shielded protocol-order transaction', () {
    expect(
      zcashExplorerTransactionUri(
        networkName: 'main',
        txidHex:
            '1f9180542beb73685e309ec65d023df3e308c2eed26aafa056ea81e078d57a47',
        txidOrder: ZcashExplorerTxidOrder.protocol,
      ).toString(),
      'https://mainnet.zcashexplorer.app/transactions/'
      '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
    );
  });

  test('does not reverse display-order transaction IDs', () {
    expect(
      zcashExplorerTransactionUri(
        networkName: 'main',
        txidHex:
            '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
        txidOrder: ZcashExplorerTxidOrder.display,
      ).toString(),
      'https://mainnet.zcashexplorer.app/transactions/'
      '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
    );
  });

  test('does not reverse malformed protocol-order transaction IDs', () {
    expect(
      zcashExplorerTransactionUri(
        networkName: 'main',
        txidHex:
            'zz7ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
        txidOrder: ZcashExplorerTxidOrder.protocol,
      ).toString(),
      'https://mainnet.zcashexplorer.app/transactions/'
      'zz7ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
    );
  });

  test('launch returns false when the platform launcher throws', () async {
    final launched = await launchZcashExplorerTransaction(
      networkName: 'main',
      txidHex:
          '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
      txidOrder: ZcashExplorerTxidOrder.display,
      launcher: (_) async => throw Exception('no browser'),
    );

    expect(launched, isFalse);
  });
}
