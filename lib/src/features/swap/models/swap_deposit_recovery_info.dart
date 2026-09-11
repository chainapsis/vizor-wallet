import '../domain/swap_contract.dart';

/// Everything a user needs to hand support when an external → ZEC deposit
/// missed its deadline. The timeout page's late-deposit explainer copies it
/// as one clipboard bundle.
class SwapDepositRecoveryInfo {
  const SwapDepositRecoveryInfo({
    required this.asset,
    required this.amountText,
    required this.depositAddress,
    required this.expiredAtText,
    this.memo,
    this.depositTxId,
  });

  final SwapAsset asset;
  final String amountText;
  final String depositAddress;

  /// Deadline with an explicit zone (UTC) — support compares it against
  /// chain timestamps, so a local-time value would be ambiguous.
  final String expiredAtText;
  final String? memo;
  final String? depositTxId;

  /// Plain-text bundle for the clipboard; one field per line so it pastes
  /// cleanly into a support form or email.
  String get bundleText {
    final lines = <String>[
      'Vizor swap recovery request',
      'Network: ${asset.chainLabel}',
      'Asset: ${asset.symbol}',
      'Amount: $amountText',
      'One-time deposit address: $depositAddress',
      if (memo?.trim().isNotEmpty ?? false) 'Memo: ${memo!.trim()}',
      if (depositTxId?.trim().isNotEmpty ?? false)
        'Deposit tx: ${depositTxId!.trim()}',
      'Deposit deadline: $expiredAtText',
    ];
    return lines.join('\n');
  }
}
