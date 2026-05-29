import 'swap_asset.dart';

enum SwapDirection { zecToExternal, externalToZec }

enum SwapQuoteMode {
  exactInput,
  exactOutput;

  String get oneClickSwapType => switch (this) {
    SwapQuoteMode.exactInput => 'EXACT_INPUT',
    SwapQuoteMode.exactOutput => 'EXACT_OUTPUT',
  };
}

extension SwapDirectionLabels on SwapDirection {
  bool get sendsZec => this == SwapDirection.zecToExternal;

  SwapDirection get toggled =>
      sendsZec ? SwapDirection.externalToZec : SwapDirection.zecToExternal;

  SwapAsset fromAsset(SwapAsset externalAsset) {
    return sendsZec ? SwapAsset.zec : externalAsset;
  }

  SwapAsset toAsset(SwapAsset externalAsset) {
    return sendsZec ? externalAsset : SwapAsset.zec;
  }

  String fromSymbol(SwapAsset externalAsset) => fromAsset(externalAsset).symbol;

  String toSymbol(SwapAsset externalAsset) => toAsset(externalAsset).symbol;
}
