import '../../core/config/network_config.dart';
import '../../core/formatting/zec_amount.dart';
import '../../core/privacy/privacy_mask.dart';
import '../../providers/sync_provider.dart';

/// Home notice for funds held until older history is checked, shared by the
/// desktop and mobile home screens; null when nothing is held or the sync
/// failed (a failure has its own notice).
String? historyHoldNoticeMessage(
  SyncState sync, {
  required bool privacyModeEnabled,
}) {
  if (sync.failure != null) return null;
  final held = sync.historyHoldBalance;
  if (held <= BigInt.zero) return null;
  final amount = hideAmountIfPrivacyMode(
    ZecAmount.fromZatoshi(held).compactBalance.amountText,
    privacyModeEnabled: privacyModeEnabled,
  );
  return '$amount $kZcashDefaultCurrencyTicker is on hold until sync '
      'finishes, because it may have been spent in history not checked yet.';
}
