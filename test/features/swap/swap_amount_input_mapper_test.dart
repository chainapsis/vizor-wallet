import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_amount_input_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  test('derives exact input counterpart and fiat texts', () {
    final state = _swapState(
      amountText: '1.2345',
      indicativeExternalPerZec: {SwapAsset.usdc: 70},
    );

    final updated = swapStateWithDerivedFiatTexts(
      swapStateWithIndicativeCounterpart(state),
    );

    expect(updated.receiveAmountText, '86.41');
    expect(updated.amountFiatText, '86.41');
    expect(updated.receiveFiatText, '86.41');
  });

  test('derives exact output counterpart with input rounded up', () {
    final state = _swapState(
      quoteMode: SwapQuoteMode.exactOutput,
      receiveAmountText: '86.41',
      indicativeExternalPerZec: {SwapAsset.usdc: 70},
    );

    final updated = swapStateWithDerivedFiatTexts(
      swapStateWithIndicativeCounterpart(state),
    );

    expect(updated.amountText, '1.2345');
    expect(updated.amountFiatText, '86.41');
    expect(updated.receiveFiatText, '86.41');
  });

  test('fiat mode toggles both sides and preserves entered fiat text', () {
    final state = swapStateWithDerivedFiatTexts(
      _swapState(
        amountText: '2.0000',
        receiveAmountText: '140.00',
        indicativeExternalPerZec: {SwapAsset.usdc: 70},
      ),
    );

    final fiatState = swapStateWithToggledFiatInputMode(
      state,
      SwapAmountInputSide.pay,
    );
    final edited = fiatState.copyWith(amountFiatText: '35');
    final tokenState = swapStateWithTokenAmountsForFiatModes(edited);

    expect(fiatState.amountInputMode, SwapAmountInputMode.fiat);
    expect(fiatState.receiveAmountInputMode, SwapAmountInputMode.fiat);
    expect(fiatState.amountFiatText, '140');
    expect(fiatState.receiveFiatText, '140');
    expect(tokenState.amountText, '0.5000');
  });
}

SwapState _swapState({
  SwapDirection direction = SwapDirection.zecToExternal,
  SwapQuoteMode quoteMode = SwapQuoteMode.exactInput,
  String amountText = '',
  String receiveAmountText = '',
  Map<SwapAsset, double> indicativeExternalPerZec = const {},
}) {
  return SwapState(
    direction: direction,
    quoteMode: quoteMode,
    amountText: amountText,
    receiveAmountText: receiveAmountText,
    destinationText: '0xrecipient',
    externalAsset: SwapAsset.usdc,
    indicativeExternalPerZec: indicativeExternalPerZec,
    reviewVisible: false,
    intents: const [],
  );
}
