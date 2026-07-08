import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  const validEvmRecipient = '0x52908400098527886E0F7030069857D2E4169EE7';

  test('blocks review when token amount exceeds asset decimals', () {
    const state = SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '105.1234567',
      destinationText: validEvmRecipient,
      externalAsset: SwapAsset.usdc,
      reviewVisible: false,
      intents: [],
      quoteMode: SwapQuoteMode.exactOutput,
    );

    expect(
      state.quoteAmountPrecisionError,
      'USDC supports up to 6 decimal places.',
    );
    expect(state.canReviewQuote, isFalse);

    final valid = state.copyWith(receiveAmountText: '105.123456');

    expect(valid.quoteAmountPrecisionError, isNull);
    expect(valid.canReviewQuote, isTrue);
  });

  test('blocks review when destination address format is invalid for chain',
      () {
    const state = SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '105.123456',
      destinationText: '0xrecipient',
      externalAsset: SwapAsset.usdc,
      reviewVisible: false,
      intents: [],
      quoteMode: SwapQuoteMode.exactOutput,
    );

    expect(state.destinationAddressFormatError, isNotNull);
    expect(state.canReviewQuote, isFalse);

    final fixed = state.copyWith(destinationText: validEvmRecipient);

    expect(fixed.destinationAddressFormatError, isNull);
    expect(fixed.canReviewQuote, isTrue);
  });

  test(
    'formats slippage amounts using token decimals before display floors',
    () {
      final sendZecQuote = SwapQuote.estimate(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        amount: 0.002,
        slippageBps: 50,
      );

      expect(sendZecQuote.slippageToleranceText, '0.00001 ZEC (0.5%)');

      final receiveZecQuote = SwapQuote.estimate(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        amount: 0.1,
        externalPerZec: 50,
        slippageBps: 50,
      );

      expect(receiveZecQuote.slippageToleranceText, '0.0005 USDC (0.5%)');
    },
  );

  test('warns when flex-input live quote changes the sell amount', () {
    final state = SwapState(
      direction: SwapDirection.externalToZec,
      amountText: '1.5',
      receiveAmountText: '',
      destinationText: validEvmRecipient,
      externalAsset: SwapAsset.usdc,
      reviewVisible: true,
      intents: const [],
      quoteMode: SwapQuoteMode.flexInput,
      reviewQuote: SwapQuote.estimate(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        mode: SwapQuoteMode.flexInput,
        amount: 2,
      ),
    );

    expect(
      state.reviewAmountDifferenceWarning,
      'Live quote uses 2.00 USDC instead of 1.50 USDC. Check the guaranteed minimum before you continue.',
    );
  });
}
