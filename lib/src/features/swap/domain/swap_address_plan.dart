import 'swap_contract.dart';

enum SwapZecStagingAddressPolicy { rotatingWalletUnifiedAddress }

enum SwapZecShieldingPolicy { notRequired }

class SwapAddressPlan {
  const SwapAddressPlan({
    required this.direction,
    required this.externalAsset,
    required this.userExternalAddress,
    required this.walletZecAddress,
    required this.zecStagingAddressPolicy,
    required this.zecShieldingPolicy,
    required this.oneClickRecipient,
    required this.oneClickRefundTo,
  });

  factory SwapAddressPlan.fromUserInput({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required String userExternalAddress,
    required String walletZecAddress,
    SwapZecStagingAddressPolicy zecStagingAddressPolicy =
        SwapZecStagingAddressPolicy.rotatingWalletUnifiedAddress,
    SwapZecShieldingPolicy zecShieldingPolicy =
        SwapZecShieldingPolicy.notRequired,
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
      zecStagingAddressPolicy: zecStagingAddressPolicy,
      zecShieldingPolicy: zecShieldingPolicy,
      oneClickRecipient: direction.sendsZec ? external : walletZec,
      oneClickRefundTo: direction.sendsZec ? walletZec : external,
    );
  }

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final String userExternalAddress;
  final String walletZecAddress;
  final SwapZecStagingAddressPolicy zecStagingAddressPolicy;
  final SwapZecShieldingPolicy zecShieldingPolicy;
  final String oneClickRecipient;
  final String oneClickRefundTo;

  bool get zecDeliveryIsDirectShielded =>
      !direction.sendsZec &&
      zecShieldingPolicy == SwapZecShieldingPolicy.notRequired;

  String get userInputLabel => direction.sendsZec
      ? 'Destination'
      : '${externalAsset.symbol} refund address';

  String get userInputHint => direction.sendsZec
      ? 'External ${externalAsset.symbol} address or account'
      : 'Refund address on the ${externalAsset.symbol} source chain';

  String get deliverySummary {
    if (zecDeliveryIsDirectShielded) {
      return 'ZEC arrives directly at the shielded wallet address';
    }
    return '${externalAsset.symbol} is delivered to the external destination';
  }

  String get reviewDeliveryValue {
    if (zecDeliveryIsDirectShielded) return 'shielded wallet address';
    return userExternalAddress;
  }

  SwapQuoteRequest toQuoteRequest({
    required double sellAmount,
    String? sellAmountText,
    bool dryRun = false,
    int? slippageBps,
    Duration? deadline,
  }) {
    return SwapQuoteRequest(
      direction: direction,
      externalAsset: externalAsset,
      sellAmount: sellAmount,
      sellAmountText: sellAmountText,
      destination: oneClickRecipient,
      refundAddress: oneClickRefundTo,
      dryRun: dryRun,
      slippageBps: slippageBps,
      deadline: deadline,
    );
  }
}
