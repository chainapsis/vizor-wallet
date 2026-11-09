import '../../../core/l10n/l10n.dart';

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

  String label(AppLocalizations l10n) => switch (this) {
    SwapActivityReturnTarget.swap => l10n.navSwap,
    SwapActivityReturnTarget.pay => l10n.navPay,
    SwapActivityReturnTarget.activity => l10n.navActivity,
    SwapActivityReturnTarget.home => l10n.navHome,
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
  const PayComposerNavigationArgs({required this.preservePreparedComposer});

  final bool preservePreparedComposer;
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
