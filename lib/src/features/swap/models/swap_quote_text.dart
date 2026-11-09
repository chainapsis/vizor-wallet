import '../../../core/l10n/l10n.dart';
import '../domain/swap_quote.dart';

/// Words a stored quote or swap detail value. Provider amount text stays as
/// it is; a reserved token ([kSwapIncludedInRateToken],
/// [kSwapNotReportedToken], [kSwapRatePendingToken]) becomes display copy.
String swapDetailValueText(AppLocalizations l10n, String value) {
  return switch (value) {
    kSwapIncludedInRateToken => l10n.swapActivityDetailIncludedInRate,
    kSwapNotReportedToken => l10n.swapActivityNotReported,
    kSwapRatePendingToken => l10n.swapQuoteRatePending,
    _ => value,
  };
}

/// When a live quote stops holding, as a 24-hour local time.
String swapQuoteExpiryText(AppLocalizations l10n, SwapQuote quote) {
  final override = quote.expiryLabel;
  if (override != null) return override;
  final expiresAt = quote.quoteExpiresAt?.toLocal();
  if (expiresAt == null) return l10n.swapQuoteExpiryPending;
  final hour = expiresAt.hour.toString().padLeft(2, '0');
  final minute = expiresAt.minute.toString().padLeft(2, '0');
  return l10n.swapQuoteExpiresAt('$hour:$minute');
}
