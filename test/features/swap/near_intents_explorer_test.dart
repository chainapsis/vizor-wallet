import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_explorer.dart';

void main() {
  test('builds direct transaction link from the deposit address', () {
    final uri = nearIntentsExplorerUri(
      nearIntentHash:
          '5f10a282d09f1a3310f40adabc8df7ee2af3725c64a9255e9709dc0fccd04a0f',
      depositTxHash: 'zec-deposit-txid',
      depositAddress: 't1deposit',
    );

    expect(
      uri.toString(),
      'https://explorer.near-intents.org/transactions/t1deposit',
    );
  });

  test('searches by deposit tx hash when NEAR intent hash is not known', () {
    final uri = nearIntentsExplorerUri(depositTxHash: 'zec-deposit-txid');

    expect(
      uri.toString(),
      'https://explorer.near-intents.org/?search=zec-deposit-txid',
    );
  });

  test('uses the deposit address route before a tx hash is known', () {
    final uri = nearIntentsExplorerUri(depositAddress: 't1provider-deposit');

    expect(
      uri.toString(),
      'https://explorer.near-intents.org/transactions/t1provider-deposit',
    );
  });

  test('falls back to search when only an intent hash is known', () {
    final uri = nearIntentsExplorerUri(nearIntentHash: 'intent-hash');

    expect(
      uri.toString(),
      'https://explorer.near-intents.org/?search=intent-hash',
    );
  });
}
