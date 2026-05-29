import 'swap_contract.dart';

class SwapAddressPlan {
  const SwapAddressPlan({
    required this.direction,
    required this.externalAsset,
    required this.userExternalAddress,
    required this.walletZecAddress,
    required this.oneClickRecipient,
    required this.oneClickRefundTo,
  });

  factory SwapAddressPlan.fromUserInput({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required String userExternalAddress,
    required String walletZecAddress,
  }) {
    final external = userExternalAddress.trim();
    final walletZec = walletZecAddress.trim();
    if (external.isEmpty) {
      throw ArgumentError.value(
        userExternalAddress,
        'userExternalAddress',
        'must not be empty',
      );
    }
    if (walletZec.isEmpty) {
      throw ArgumentError.value(
        walletZecAddress,
        'walletZecAddress',
        'must not be empty',
      );
    }

    return SwapAddressPlan(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: external,
      walletZecAddress: walletZec,
      oneClickRecipient: direction.sendsZec ? external : walletZec,
      oneClickRefundTo: direction.sendsZec ? walletZec : external,
    );
  }

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final String userExternalAddress;
  final String walletZecAddress;
  final String oneClickRecipient;
  final String oneClickRefundTo;

  SwapQuoteRequest toQuoteRequest({
    double? amount,
    double? sellAmount,
    SwapQuoteMode mode = SwapQuoteMode.exactInput,
    String? amountText,
    String? sellAmountText,
    bool dryRun = false,
    int? slippageBps,
    Duration? deadline,
  }) {
    return SwapQuoteRequest(
      direction: direction,
      externalAsset: externalAsset,
      mode: mode,
      amount: amount,
      sellAmount: sellAmount,
      amountText: amountText,
      sellAmountText: sellAmountText,
      destination: oneClickRecipient,
      refundAddress: oneClickRefundTo,
      dryRun: dryRun,
      slippageBps: slippageBps,
      deadline: deadline,
    );
  }
}
