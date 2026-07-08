import 'swap_fiat_amount.dart';
import 'swap_models.dart';

String? swapPayTokenTextFromFiatInput(SwapState state, String fiatAmountText) {
  return swapTokenAmountTextFromFiatText(
    state,
    asset: state.direction.fromAsset(state.externalAsset),
    fiatAmountText: fiatAmountText,
  );
}

String? swapReceiveTokenTextFromFiatInput(
  SwapState state,
  String fiatAmountText,
) {
  return swapTokenAmountTextFromFiatText(
    state,
    asset: state.direction.toAsset(state.externalAsset),
    fiatAmountText: fiatAmountText,
  );
}

SwapState swapStateWithIndicativeCounterpart(SwapState next) {
  final estimate = next.draftQuote;
  if (estimate == null) {
    return next.quoteMode.usesInputAmount
        ? next.copyWith(receiveAmountText: '')
        : next.copyWith(amountText: '');
  }
  if (next.quoteMode.usesInputAmount) {
    return next.copyWith(
      receiveAmountText: estimate.receiveAsset.formatAmountDown(
        estimate.receiveAmount,
      ),
    );
  }
  return next.copyWith(
    amountText: estimate.sellAsset.formatAmountUp(estimate.sellAmount),
  );
}

SwapState swapStateWithDerivedFiatTexts(
  SwapState next, {
  bool preserveAmountFiatInput = false,
  bool preserveReceiveFiatInput = false,
}) {
  return next.copyWith(
    amountFiatText: preserveAmountFiatInput
        ? next.amountFiatText
        : swapFiatInputTextFromTokenText(
            next,
            asset: next.direction.fromAsset(next.externalAsset),
            tokenAmountText: next.amountText,
          ),
    receiveFiatText: preserveReceiveFiatInput
        ? next.receiveFiatText
        : swapFiatInputTextFromTokenText(
            next,
            asset: next.direction.toAsset(next.externalAsset),
            tokenAmountText: next.receiveAmountText,
          ),
  );
}

SwapState swapStateWithTokenAmountsForFiatModes(SwapState current) {
  var next = current;
  if (next.amountInputMode == SwapAmountInputMode.fiat) {
    final tokenText = swapPayTokenTextFromFiatInput(next, next.amountFiatText);
    next = next.copyWith(amountText: tokenText ?? '');
  }
  if (next.receiveAmountInputMode == SwapAmountInputMode.fiat) {
    final tokenText = swapReceiveTokenTextFromFiatInput(
      next,
      next.receiveFiatText,
    );
    next = next.copyWith(receiveAmountText: tokenText ?? '');
  }
  return next;
}

SwapState swapStateWithToggledFiatInputMode(
  SwapState current,
  SwapAmountInputSide side,
) {
  return switch (side) {
    SwapAmountInputSide.pay => _togglePayInputMode(current),
    SwapAmountInputSide.receive => _toggleReceiveInputMode(current),
  };
}

SwapState _togglePayInputMode(SwapState current) {
  final nextMode = current.amountInputMode == SwapAmountInputMode.token
      ? SwapAmountInputMode.fiat
      : SwapAmountInputMode.token;
  return _swapStateWithInputMode(current, nextMode);
}

SwapState _toggleReceiveInputMode(SwapState current) {
  final nextMode = current.receiveAmountInputMode == SwapAmountInputMode.token
      ? SwapAmountInputMode.fiat
      : SwapAmountInputMode.token;
  return _swapStateWithInputMode(current, nextMode);
}

SwapState _swapStateWithInputMode(
  SwapState current,
  SwapAmountInputMode nextMode,
) {
  return current.copyWith(
    amountInputMode: nextMode,
    receiveAmountInputMode: nextMode,
    amountFiatText: nextMode == SwapAmountInputMode.fiat
        ? swapFiatInputTextFromTokenText(
            current,
            asset: current.direction.fromAsset(current.externalAsset),
            tokenAmountText: current.amountText,
          )
        : current.amountFiatText,
    receiveFiatText: nextMode == SwapAmountInputMode.fiat
        ? swapFiatInputTextFromTokenText(
            current,
            asset: current.direction.toAsset(current.externalAsset),
            tokenAmountText: current.receiveAmountText,
          )
        : current.receiveFiatText,
  );
}
