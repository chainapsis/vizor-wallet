/// NEAR Intents recovery policy for funds that never reach the automatic
/// refund rail (wrong token, wrong network, expired one-time address, wrong
/// refund address). Deposits that do reach the rail — including ones that
/// land after the deadline — are refunded to the refund address regardless
/// of size; the floor applies only to manual recovery requests for user
/// error. Source: near.com/terms, "Asset Recovery" and "Failed Execution,
/// Deadlines, and Refunds".
///
/// Placement: the policy lives on the one row where the mistake it describes
/// can happen — the deposit page's "Network" row, behind its help affordance
/// (tooltip on desktop, bottom sheet on mobile). The row itself is a plain
/// fact; the post-failure surfaces offer the support bundle. Kept in one
/// place so the figure and the copy can move to remote config without
/// touching the surfaces that show them.
abstract final class SwapRefundPolicy {
  /// USD value below which NEAR will not consider a user-error recovery
  /// request. At or above it, recovery is still discretionary.
  static const recoveryFloorUsd = 300;

  static const _floorText = r'$300';

  /// Deposit page (external → ZEC): help behind the "Network" row.
  static const depositNetworkHelpTitle = 'Network';

  static String depositNetworkHelp({
    required String symbol,
    required String chainLabel,
  }) =>
      'Send $symbol on $chainLabel only. A deposit on another network or in '
      'another token isn’t returned automatically — NEAR reviews those '
      'manually, for amounts of $_floorText or more.';

  /// Deposit timeout page: a quiet prompt under the restart action that
  /// opens the late-deposit explainer (modal on desktop, sheet on mobile).
  /// Only offered when the swap's deposit details are known, since the
  /// explainer's action is the support bundle. A late deposit is still on
  /// the automatic rail, so no floor is mentioned.
  static const lateDepositPrompt = 'Made a late deposit?';
  static const lateDepositTitle = 'Late deposit';
  static const lateDepositBody =
      'Deposits that arrive after the deadline are refunded to your refund '
      'address automatically.';
  static const lateDepositSupport =
      'If nothing arrives, copy the deposit details and send them to Vizor '
      'support.';
  static const lateDepositAction = 'Copy deposit details';
  static const lateDepositSupportAction = 'Contact support';

  /// Vizor support page (email + bug-report guidance). Recovery requests
  /// reach NEAR through Vizor, not through the user directly.
  static final supportUri = Uri.parse('https://vizor.cash/support/');
}
