import '../../../core/config/fiat_currencies.dart';
import 'swap_fiat_amount.dart';
import 'swap_models.dart';

String? swapPayTokenTextFromFiatInput(
  SwapState state,
  String fiatAmountText, {
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  return swapTokenAmountTextFromFiatText(
    state,
    asset: state.direction.fromAsset(state.externalAsset),
    fiatAmountText: fiatAmountText,
    fiatDisplay: fiatDisplay,
  );
}

String? swapReceiveTokenTextFromFiatInput(
  SwapState state,
  String fiatAmountText, {
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  return swapTokenAmountTextFromFiatText(
    state,
    asset: state.direction.toAsset(state.externalAsset),
    fiatAmountText: fiatAmountText,
    fiatDisplay: fiatDisplay,
  );
}

SwapState swapStateWithIndicativeCounterpart(SwapState next) {
  final estimate = next.draftQuote;
  if (estimate == null) {
    return next.quoteMode == SwapQuoteMode.exactInput
        ? next.copyWith(receiveAmountText: '')
        : next.copyWith(amountText: '');
  }
  if (next.quoteMode == SwapQuoteMode.exactInput) {
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
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  return next.copyWith(
    amountFiatText: preserveAmountFiatInput
        ? next.amountFiatText
        : swapFiatInputTextFromTokenText(
            next,
            asset: next.direction.fromAsset(next.externalAsset),
            tokenAmountText: next.amountText,
            fiatDisplay: fiatDisplay,
          ),
    receiveFiatText: preserveReceiveFiatInput
        ? next.receiveFiatText
        : swapFiatInputTextFromTokenText(
            next,
            asset: next.direction.toAsset(next.externalAsset),
            tokenAmountText: next.receiveAmountText,
            fiatDisplay: fiatDisplay,
          ),
  );
}

SwapState swapStateWithTokenAmountsForFiatModes(
  SwapState current, {
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  var next = current;
  if (next.amountInputMode == SwapAmountInputMode.fiat) {
    final tokenText = swapPayTokenTextFromFiatInput(
      next,
      next.amountFiatText,
      fiatDisplay: fiatDisplay,
    );
    next = next.copyWith(amountText: tokenText ?? '');
  }
  if (next.receiveAmountInputMode == SwapAmountInputMode.fiat) {
    final tokenText = swapReceiveTokenTextFromFiatInput(
      next,
      next.receiveFiatText,
      fiatDisplay: fiatDisplay,
    );
    next = next.copyWith(receiveAmountText: tokenText ?? '');
  }
  return next;
}

SwapState swapStateWithToggledFiatInputMode(
  SwapState current,
  SwapAmountInputSide side, {
  FiatDisplay fiatDisplay = kUsdFiatDisplay,
}) {
  final nextMode = switch (side) {
    SwapAmountInputSide.pay =>
      current.amountInputMode == SwapAmountInputMode.token
          ? SwapAmountInputMode.fiat
          : SwapAmountInputMode.token,
    SwapAmountInputSide.receive =>
      current.receiveAmountInputMode == SwapAmountInputMode.token
          ? SwapAmountInputMode.fiat
          : SwapAmountInputMode.token,
  };
  return _swapStateWithInputMode(current, nextMode, fiatDisplay: fiatDisplay);
}

SwapState _swapStateWithInputMode(
  SwapState current,
  SwapAmountInputMode nextMode, {
  required FiatDisplay fiatDisplay,
}) {
  return current.copyWith(
    amountInputMode: nextMode,
    receiveAmountInputMode: nextMode,
    amountFiatText: nextMode == SwapAmountInputMode.fiat
        ? swapFiatInputTextFromTokenText(
            current,
            asset: current.direction.fromAsset(current.externalAsset),
            tokenAmountText: current.amountText,
            fiatDisplay: fiatDisplay,
          )
        : current.amountFiatText,
    receiveFiatText: nextMode == SwapAmountInputMode.fiat
        ? swapFiatInputTextFromTokenText(
            current,
            asset: current.direction.toAsset(current.externalAsset),
            tokenAmountText: current.receiveAmountText,
            fiatDisplay: fiatDisplay,
          )
        : current.receiveFiatText,
  );
}
