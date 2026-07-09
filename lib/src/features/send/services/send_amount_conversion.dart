import '../../../core/config/fiat_currencies.dart';
import '../../../core/formatting/number_format.dart';
import '../../../core/formatting/zec_amount.dart';

/// Shared fiat<->zatoshi conversion for the send screens (desktop + mobile).
/// All text is denominated in the resolved display currency
/// (`zecHomeFiatDisplayCurrencyProvider`) — pass the same currency the unit
/// price is denominated in (`zecHomeFiatUnitPriceProvider`).
BigInt? sendZatoshiFromFiatText(String text, double? zecUnitPrice) {
  final normalized = text.trim();
  if (normalized.isEmpty || normalized == '.' || normalized == '0.') {
    return null;
  }
  final fiat = double.tryParse(
    normalized.startsWith('.') ? '0$normalized' : normalized,
  );
  if (fiat == null ||
      !fiat.isFinite ||
      fiat <= 0 ||
      zecUnitPrice == null ||
      !zecUnitPrice.isFinite ||
      zecUnitPrice <= 0) {
    return null;
  }

  final zatoshi = (fiat / zecUnitPrice) * zatoshiPerZec.toDouble();
  if (!zatoshi.isFinite || zatoshi <= 0) return null;
  return BigInt.from(zatoshi.floor());
}

/// "0" (KRW) / "0.00" (USD)-style zero entry text in [currency].
String sendZeroFiatText(FiatCurrency currency) =>
    (0.0).toStringAsFixed(currency.maxDecimals);

String sendFiatInputTextForZatoshi(
  BigInt zatoshi,
  double zecUnitPrice,
  FiatCurrency currency,
) {
  final fiat = zatoshi.toDouble() / zatoshiPerZec.toDouble() * zecUnitPrice;
  if (!fiat.isFinite || fiat <= 0) return '';
  return fiat.toStringAsFixed(currency.maxDecimals);
}

String sendSendableFiatInputTextForZatoshi(
  BigInt zatoshi,
  double zecUnitPrice,
  FiatCurrency currency,
) {
  final text = sendFiatInputTextForZatoshi(zatoshi, zecUnitPrice, currency);
  return text == sendZeroFiatText(currency) ? '' : text;
}

/// Grouped display text ("1,234.56" USD / "136,500" KRW) for meta rows.
String sendFiatDisplayTextForZatoshi(
  BigInt zatoshi,
  double zecUnitPrice,
  FiatCurrency currency,
) {
  final raw = sendFiatInputTextForZatoshi(zatoshi, zecUnitPrice, currency);
  if (raw.isEmpty) return sendZeroFiatText(currency);
  final parts = raw.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  final grouped = formatGroupedInteger(whole);
  if (currency.maxDecimals == 0 || parts.length < 2) return grouped;
  return '$grouped.${parts[1]}';
}
