import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zcash_wallet/src/features/swap/domain/near_intents_explorer.dart';

void main() {
  test('opens the deposit address as a direct transaction route', () {
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

  test('searches by deposit tx hash when it is the only target', () {
    final uri = nearIntentsExplorerUri(depositTxHash: 'zec-deposit-txid');

    expect(
      uri.toString(),
      'https://explorer.near-intents.org/?search=zec-deposit-txid',
    );
  });

  test(
    'searches by NEAR intent hash when no direct transaction target exists',
    () {
      final uri = nearIntentsExplorerUri(nearIntentHash: 'intent-hash');

      expect(
        uri.toString(),
        'https://explorer.near-intents.org/?search=intent-hash',
      );
    },
  );

  test('uses the deposit address route before a tx hash is known', () {
    final uri = nearIntentsExplorerUri(depositAddress: 't1provider-deposit');

    expect(
      uri.toString(),
      'https://explorer.near-intents.org/transactions/t1provider-deposit',
    );
  });

  test(
    'launches explorer externally so the browser owns the new tab',
    () async {
      Uri? launchedUri;
      LaunchMode? launchMode;

      final launched = await launchNearIntentsExplorer(
        depositAddress: 't1provider-deposit',
        launcher: (uri, {required mode}) async {
          launchedUri = uri;
          launchMode = mode;
          return true;
        },
      );

      expect(launched, isTrue);
      expect(
        launchedUri.toString(),
        'https://explorer.near-intents.org/transactions/t1provider-deposit',
      );
      expect(launchMode, LaunchMode.externalApplication);
    },
  );

  test('launch returns false when there is no explorer target', () async {
    var launchCount = 0;

    final launched = await launchNearIntentsExplorer(
      launcher: (uri, {required mode}) async {
        launchCount++;
        return true;
      },
    );

    expect(launched, isFalse);
    expect(launchCount, 0);
  });
}
