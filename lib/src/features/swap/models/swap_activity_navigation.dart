enum SwapActivityReturnTarget {
  swap,
  pay,
  activity,
  home;

  String get queryValue => switch (this) {
    SwapActivityReturnTarget.swap => 'swap',
    SwapActivityReturnTarget.pay => 'pay',
    SwapActivityReturnTarget.activity => 'activity',
    SwapActivityReturnTarget.home => 'home',
  };

  String get label => switch (this) {
    SwapActivityReturnTarget.swap => 'Swap',
    SwapActivityReturnTarget.pay => 'Pay',
    SwapActivityReturnTarget.activity => 'Activity',
    SwapActivityReturnTarget.home => 'Home',
  };

  String get path => switch (this) {
    SwapActivityReturnTarget.swap => '/swap',
    SwapActivityReturnTarget.pay => '/pay',
    SwapActivityReturnTarget.activity => '/activity',
    SwapActivityReturnTarget.home => '/home',
  };

  static SwapActivityReturnTarget fromQueryValue(String? value) {
    return switch (value) {
      'swap' => SwapActivityReturnTarget.swap,
      'pay' => SwapActivityReturnTarget.pay,
      'home' => SwapActivityReturnTarget.home,
      _ => SwapActivityReturnTarget.activity,
    };
  }
}

class PayComposerNavigationArgs {
  const PayComposerNavigationArgs({
    required this.preservePreparedComposer,
    this.paymentRequestId,
    this.showPreparedReview = false,
    this.reviewAfterAmount = false,
  });

  final bool preservePreparedComposer;
  final String? paymentRequestId;
  final bool showPreparedReview;

  /// A request's missing amount may go straight to review once. Explicit
  /// editing and returning from review must leave recipient selection reachable.
  final bool reviewAfterAmount;
}

const swapActivityReturnQueryKey = 'from';
const swapActivitySignQueryKey = 'sign';
const swapActivitySignZecDepositValue = 'zecDeposit';

Uri swapActivityDetailUri({
  required String intentId,
  required SwapActivityReturnTarget returnTarget,
  bool autoSignZecDeposit = false,
}) {
  return Uri(
    path: '/activity/swap/${Uri.encodeComponent(intentId)}',
    queryParameters: {
      swapActivityReturnQueryKey: returnTarget.queryValue,
      if (autoSignZecDeposit)
        swapActivitySignQueryKey: swapActivitySignZecDepositValue,
    },
  );
}
