import '../../../core/l10n/l10n.dart';

/// Which end of a swap uses a one-time Zcash address.
enum OneTimeAddressRole {
  /// The payout of a swap into ZEC.
  payout,

  /// The refund of a swap that sends ZEC.
  refund;

  /// The composer's short label, the same for both ends; [explanation] says
  /// what the address is for.
  String label(AppLocalizations l10n) => l10n.swapOneTimeAddressLabel;

  /// The review and status label, which names the refund end.
  String detailLabel(AppLocalizations l10n) => switch (this) {
    payout => l10n.swapOneTimeAddressLabel,
    refund => l10n.swapOneTimeRefundAddressLabel,
  };

  String explanation(AppLocalizations l10n) => switch (this) {
    payout => l10n.swapOneTimeAddressPayoutExplanation,
    refund => l10n.swapOneTimeAddressRefundExplanation,
  };
}
