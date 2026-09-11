import '../../../core/payments/cross_chain_payment_request.dart';
import '../../swap/domain/swap_asset.dart';

class PaymentRequestResolution {
  const PaymentRequestResolution({
    this.asset,
    this.amountText,
    this.message,
    this.needsNetwork = false,
  });
  final SwapAsset? asset;
  final String? amountText;
  final String? message;
  final bool needsNetwork;
  bool get isReady => asset != null && message == null;

  /// Indicative cost from the resolved asset's market price, excluding fees.
  /// Missing prices must not fall back to static example exchange rates.
  double? estimateZecAmount(Map<SwapAsset, double> externalPerZec) {
    if (!isReady || needsNetwork) return null;
    final rate = externalPerZec[asset];
    final amount = double.tryParse(amountText ?? '');
    if (rate == null ||
        !rate.isFinite ||
        rate <= 0 ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0) {
      return null;
    }
    final estimate = amount / rate;
    return estimate.isFinite && estimate > 0 ? estimate : null;
  }
}

PaymentRequestResolution resolveCrossChainPaymentRequest(
  CrossChainPaymentRequest request,
  List<SwapAsset> assets, {
  String? selectedChain,
}) {
  if (request.unsupportedReason case final reason?) {
    return PaymentRequestResolution(message: reason);
  }
  String? chain = request.chain;
  if (request.isEvm) {
    if (request.chainId case final chainId?) {
      chain = evmPaymentNetworks[chainId]?.chain;
      if (chain == null) {
        return const PaymentRequestResolution(
          message:
              'This request uses a network that Vizor does not support. Ask the sender for a supported network.',
        );
      }
    } else {
      if (!evmPaymentNetworks.values.any(
        (network) => network.chain == selectedChain,
      )) {
        return PaymentRequestResolution(
          needsNetwork: true,
          message: request.amount == null
              ? 'Select the receiving network, then enter an amount.'
              : 'Select the receiving network to see the payment amount.',
        );
      }
      chain = selectedChain;
    }
  }
  final matches = assets.where((asset) {
    if (asset.chainTicker != chain || asset.assetId == null) return false;
    final contract = request.contractAddress;
    if (contract != null) {
      final address = asset.contractAddress;
      return address != null &&
          (chain == 'sol'
              ? address == contract
              : address.toLowerCase() == contract.toLowerCase());
    }
    final nativeSymbols = switch (chain) {
      'eth' || 'arb' || 'base' || 'op' => {'ETH'},
      'bsc' => {'BNB'},
      'pol' => {'POL', 'MATIC'},
      'xlayer' => {'OKB'},
      'avax' => {'AVAX'},
      'btc' => {'BTC'},
      'ltc' => {'LTC'},
      'sol' => {'SOL'},
      _ => <String>{},
    };
    return asset.contractAddress == null &&
        nativeSymbols.contains(asset.symbol.toUpperCase());
  }).toList();
  if (matches.length != 1) {
    return PaymentRequestResolution(
      message: matches.isEmpty
          ? 'This payment asset is not available in Vizor. Ask the sender for another supported asset or use another wallet.'
          : 'More than one asset matches this request. Vizor cannot safely choose one. Ask the sender for a more specific request.',
    );
  }
  final asset = matches.single;
  try {
    return PaymentRequestResolution(
      asset: asset,
      amountText: request.amount?.forDecimals(asset.decimals),
    );
  } on CrossChainPaymentParseException {
    return const PaymentRequestResolution(
      message:
          'The requested amount has more decimal places than this asset supports. Ask the sender for a corrected request.',
    );
  }
}
