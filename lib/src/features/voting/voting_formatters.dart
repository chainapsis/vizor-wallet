import '../../core/formatting/number_format.dart';
import '../../core/formatting/zec_amount.dart';

/// Formats raw zatoshi voting power as e.g. `12.5 ZEC`.
///
/// Delegates to [ZecAmount] for the decimal formatting. The denomination is
/// kept as the literal `ZEC` to preserve existing output across networks.
String formatVotingPower(BigInt zatoshi) {
  return ZecAmount.fromZatoshi(
    zatoshi,
  ).pretty(denomStyle: ZecDenomStyle.upper, denomination: 'ZEC').toString();
}

String formatBlockHeight(int height) => formatGroupedInteger(height);

String formatVotingWalletSyncProgress({
  required double? progress,
  bool stalled = false,
}) {
  final normalizedProgress = progress?.clamp(0.0, 1.0).toDouble();
  final percentage = normalizedProgress == null
      ? null
      : (normalizedProgress * 100).floor().clamp(0, 100);
  final progressText = percentage == null
      ? 'Wallet sync'
      : 'Wallet sync: $percentage%';
  if (stalled) {
    return '$progressText. Sync has stopped advancing. Voting power will be '
        'calculated automatically when sync resumes.';
  }
  if (percentage == null) {
    return 'Wallet synchronization is in progress. Voting power will be '
        'calculated once the snapshot height is reached.';
  }
  return '$progressText. Voting power will be calculated once the snapshot '
      'height is reached.';
}
