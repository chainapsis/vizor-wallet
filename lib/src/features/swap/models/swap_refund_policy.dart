import 'swap_deposit_recovery_info.dart';

/// NEAR Intents recovery policy. User-error recovery requests below $300 in
/// USD value are not considered; requests at or above that value remain
/// not guaranteed. Late deposits may be refunded, but no refund is guaranteed.
/// Sources: near.com/terms, "Incorrect Transfers, Unsupported Assets, and No
/// Recovery Obligation" and "Failed Execution, Deadlines, and Refunds";
/// docs.near-intents.org/security-compliance/terms-of-service, section 12.4.
///
/// The deposit page offers network guidance; post-failure surfaces offer the
/// support bundle. Kept together so policy copy remains consistent.
abstract final class SwapRefundPolicy {
  /// USD value below which NEAR will not consider a user-error recovery
  /// request. At or above it, NEAR may still decline the request.
  static const recoveryFloorUsd = 300;

  static const depositNetworkHelpTitle = 'Deposit network';

  static String depositNetworkHint({
    required String symbol,
    required String chainLabel,
  }) => '$symbol on $chainLabel only';

  static String depositNetworkHelp({
    required String symbol,
    required String chainLabel,
  }) =>
      'Send $symbol on $chainLabel to this address. Deposits made with a '
      'different token or network may not be credited.\n\n'
      'NEAR considers recovery requests for these deposits only at '
      '\$$recoveryFloorUsd or more. Recovery isn’t guaranteed.';

  /// Deposit timeout page: a quiet prompt under the restart action that
  /// opens the deposit recovery explainer (modal on desktop, sheet on mobile).
  /// Only offered when the swap's deposit details are known, since the
  /// explainer's action is the support bundle. The user-error recovery floor
  /// does not describe the late-deposit refund attempt.
  static const lateDepositPrompt = 'Sent a deposit?';
  static const lateDepositTitle = 'Check your deposit';
  static const lateDepositBody =
      'Check the transaction in the wallet you sent from. If your deposit '
      'arrived late, NEAR may try to refund it to your refund address.';
  static const lateDepositSupport =
      'If it’s confirmed and no swap or refund appears, email support.';
  static const lateDepositAction = 'Copy deposit details';
  static const lateDepositSupportAction = 'Email support';

  /// Vizor's published support address. The user reviews and sends the draft
  /// in their email app; opening it does not submit a recovery request.
  static const supportEmail = 'support@vizor.cash';

  static Uri supportEmailUri(SwapDepositRecoveryInfo info) {
    final depositTxId = info.depositTxId?.trim();
    final body = [
      'Hello Vizor support,',
      '',
      'Could you check this swap deposit? I don’t see a completed swap or refund.',
      '',
      'Transaction hash: ${depositTxId == null || depositTxId.isEmpty ? '[Add the hash from the sending wallet, if available]' : depositTxId}',
      'Expected deposit: ${info.amountText} on ${info.asset.chainLabel}',
      'One-time deposit address: ${info.depositAddress}',
      if (info.memo?.trim().isNotEmpty ?? false) 'Memo: ${info.memo!.trim()}',
      'Deposit deadline: ${info.expiredAtText}',
      '',
      'Additional details (optional):',
      '[Add anything else that may help]',
    ].join('\n');
    final query =
        <String, String>{'subject': 'Vizor swap deposit check', 'body': body}
            .entries
            .map(
              (entry) =>
                  '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
            )
            .join('&');
    return Uri(scheme: 'mailto', path: supportEmail, query: query);
  }

  /// Fallback when the device has no configured email app.
  static final supportUri = Uri.parse('https://vizor.cash/support/');
}
