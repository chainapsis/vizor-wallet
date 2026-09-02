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
      'https://cipherscan.app/tx/'
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
      'https://testnet.cipherscan.app/tx/'
      '3b73c8a9b97669586f626db527361744a413af21b483ab25b818f4ac5fad8860',
    );
  });

  test('uses testnet explorer host for regtest transaction links', () {
    expect(
      zcashExplorerTransactionUri(
        networkName: 'regtest',
        txidHex:
            '6088ad5facf418b825ab83b421af13a444173627b56d626f586976b9a9c8733b',
        txidOrder: ZcashExplorerTxidOrder.protocol,
      ).toString(),
      'https://testnet.cipherscan.app/tx/'
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
      'https://cipherscan.app/tx/'
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
      'https://cipherscan.app/tx/'
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
      'https://cipherscan.app/tx/'
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

  test('origin-only custom template appends /tx/{txid}', () {
    expect(
      normalizeExplorerUrlTemplate('https://explorer.example'),
      'https://explorer.example/tx/{txid}',
    );
    expect(
      zcashExplorerTransactionUri(
        networkName: 'main',
        txidHex:
            '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
        txidOrder: ZcashExplorerTxidOrder.display,
        customTemplate: 'https://explorer.example',
      ).toString(),
      'https://explorer.example/tx/'
      '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
    );
  });

  test('substitutes {txid} and {txHash} placeholders', () {
    const txid =
        '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f';
    expect(
      zcashExplorerTransactionUri(
        networkName: 'main',
        txidHex: txid,
        txidOrder: ZcashExplorerTxidOrder.display,
        customTemplate: 'https://self-hosted.example/zcash/{txHash}',
      ).toString(),
      'https://self-hosted.example/zcash/$txid',
    );
  });

  test('replaces a concrete 64-hex path tail with {txid}', () {
    expect(
      normalizeExplorerUrlTemplate(
        'https://cipherscan.app/tx/'
        '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
      ),
      'https://cipherscan.app/tx/{txid}',
    );
  });

  test('adds https when the scheme is omitted', () {
    expect(
      normalizeExplorerUrlTemplate('my-explorer.local/tx/{txid}'),
      'https://my-explorer.local/tx/{txid}',
    );
  });

  test('rejects non-http schemes', () {
    expect(
      () => normalizeExplorerUrlTemplate('javascript:alert(1)'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Enter an http or https URL.',
        ),
      ),
    );
  });

  test('settings label is CipherScan until a custom host is set', () {
    expect(
      explorerSettingsLabel('', networkName: 'main'),
      kDefaultZcashExplorerLabel,
    );
    expect(
      explorerSettingsLabel(
        'https://privacy.example/tx/{txid}',
        networkName: 'main',
      ),
      'privacy.example',
    );
  });

  test('launch uses the custom template when provided', () async {
    final launched = <Uri>[];
    final opened = await launchZcashExplorerTransaction(
      networkName: 'main',
      txidHex:
          '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
      txidOrder: ZcashExplorerTxidOrder.display,
      customTemplate: 'http://127.0.0.1:8080/tx/{txid}',
      launcher: (uri) async {
        launched.add(uri);
        return true;
      },
    );

    expect(opened, isTrue);
    expect(
      launched.single.toString(),
      'http://127.0.0.1:8080/tx/'
      '477ad578e081ea56a0af6ad2eec208e3f33d025dc69e305e6873eb2b5480911f',
    );
  });
}
