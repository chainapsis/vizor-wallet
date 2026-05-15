import 'swap_contract.dart';

enum SwapZecStagingAddressPolicy {
  currentWalletTransparentAddress,
  rotatingWalletTransparentAddress,
}

enum SwapZecShieldingPolicy { promptAfterArrival, automaticAfterArrival }

class SwapAddressPlan {
  const SwapAddressPlan({
    required this.direction,
    required this.externalAsset,
    required this.userExternalAddress,
    required this.walletTransparentAddress,
    required this.zecStagingAddressPolicy,
    required this.zecShieldingPolicy,
    required this.oneClickRecipient,
    required this.oneClickRefundTo,
  });

  factory SwapAddressPlan.fromUserInput({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required String userExternalAddress,
    required String walletTransparentAddress,
    SwapZecStagingAddressPolicy zecStagingAddressPolicy =
        SwapZecStagingAddressPolicy.currentWalletTransparentAddress,
    SwapZecShieldingPolicy zecShieldingPolicy =
        SwapZecShieldingPolicy.promptAfterArrival,
  }) {
    final external = userExternalAddress.trim();
    final walletStaging = walletTransparentAddress.trim();
    if (external.isEmpty) {
      throw ArgumentError.value(
        userExternalAddress,
        'userExternalAddress',
        'must not be empty',
      );
    }
    if (walletStaging.isEmpty) {
      throw ArgumentError.value(
        walletTransparentAddress,
        'walletTransparentAddress',
        'must not be empty',
      );
    }

    return SwapAddressPlan(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: external,
      walletTransparentAddress: walletStaging,
      zecStagingAddressPolicy: zecStagingAddressPolicy,
      zecShieldingPolicy: zecShieldingPolicy,
      oneClickRecipient: direction.sendsZec ? external : walletStaging,
      oneClickRefundTo: direction.sendsZec ? walletStaging : external,
    );
  }

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final String userExternalAddress;
  final String walletTransparentAddress;
  final SwapZecStagingAddressPolicy zecStagingAddressPolicy;
  final SwapZecShieldingPolicy zecShieldingPolicy;
  final String oneClickRecipient;
  final String oneClickRefundTo;

  bool get zecDeliveryUsesWalletStaging => !direction.sendsZec;

  bool get zecStagingIsRotating =>
      zecStagingAddressPolicy ==
      SwapZecStagingAddressPolicy.rotatingWalletTransparentAddress;

  bool get zecShieldingIsAutomatic =>
      zecShieldingPolicy == SwapZecShieldingPolicy.automaticAfterArrival;

  String get zecStagingLabel => zecStagingIsRotating
      ? 'reserved wallet receive address'
      : 'wallet receive address';

  String get zecShieldingLabel =>
      zecShieldingIsAutomatic ? 'auto-shield' : 'shield prompt';

  String get userInputLabel => direction.sendsZec
      ? 'Destination'
      : '${externalAsset.symbol} refund address';

  String get userInputHint => direction.sendsZec
      ? 'External ${externalAsset.symbol} address or account'
      : 'Refund address on the ${externalAsset.symbol} source chain';

  String get deliverySummary => zecDeliveryUsesWalletStaging
      ? 'ZEC arrives at the $zecStagingLabel; $zecShieldingLabel follows'
      : '${externalAsset.symbol} is delivered to the external destination';

  String get reviewDeliveryValue => zecDeliveryUsesWalletStaging
      ? '$zecStagingLabel; $zecShieldingLabel follows'
      : userExternalAddress;

  SwapQuoteRequest toQuoteRequest({
    required double sellAmount,
    bool dryRun = false,
    int? slippageBps,
    Duration? deadline,
  }) {
    return SwapQuoteRequest(
      direction: direction,
      externalAsset: externalAsset,
      sellAmount: sellAmount,
      destination: oneClickRecipient,
      refundAddress: oneClickRefundTo,
      dryRun: dryRun,
      slippageBps: slippageBps,
      deadline: deadline,
    );
  }
}
