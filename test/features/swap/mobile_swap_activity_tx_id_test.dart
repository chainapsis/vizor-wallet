@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations_en.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  // The "Tx ID" detail row is a mobile-only addition; the desktop mapper test
  // (swap_activity_status_mapper_test.dart) asserts it is absent on desktop.
  // This mirrors that coverage in the mobile token lane, where the row exists.
  test('mobile adds a NEAR Intents explorer link to the tx id detail row', () {
    final presentation = swapActivityStatusPresentationForIntent(
      l10n: AppLocalizationsEn(),
      _state(),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1provider-deposit',
        nearIntentHash: 'intent-hash-123',
        originChainTxHash: 'zec-origin-txid',
      ),
    );

    final txId = presentation.details.singleWhere(
      (row) => row.label == 'Tx ID',
    );
    expect(txId.value, 't1provider-deposit');
    expect(
      txId.linkUri.toString(),
      'https://explorer.near-intents.org/transactions/t1provider-deposit',
    );
  });
}

SwapState _state() {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    indicativeExternalPerZec: const {},
  );
}

SwapIntent _intent({
  required SwapIntentStatus status,
  required SwapDirection direction,
  required SwapAsset externalAsset,
  String? depositAddress,
  String? nearIntentHash,
  String? originChainTxHash,
}) {
  return SwapIntent(
    id: 'swap-activity',
    pair: 'ZEC -> USDC',
    sellAmount: '2.0000 ZEC',
    receiveEstimate: '140.00 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Next action',
    direction: direction,
    externalAsset: externalAsset,
    depositAddress: depositAddress,
    minimumReceiveText: '140.00 USDC',
    nearIntentHash: nearIntentHash,
    originChainTxHash: originChainTxHash,
  );
}
