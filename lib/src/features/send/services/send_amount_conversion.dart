import '../../../core/formatting/number_format.dart';
import '../../../core/formatting/zec_amount.dart';

BigInt? sendZatoshiFromUsdText(String text, double? zecUsdUnitPrice) {
  final normalized = text.trim();
  if (normalized.isEmpty || normalized == '.' || normalized == '0.') {
    return null;
  }
  final usd = double.tryParse(
    normalized.startsWith('.') ? '0$normalized' : normalized,
  );
  if (usd == null ||
      !usd.isFinite ||
      usd <= 0 ||
      zecUsdUnitPrice == null ||
      !zecUsdUnitPrice.isFinite ||
      zecUsdUnitPrice <= 0) {
    return null;
  }

  final zatoshi = (usd / zecUsdUnitPrice) * zatoshiPerZec.toDouble();
  if (!zatoshi.isFinite || zatoshi <= 0) return null;
  return BigInt.from(zatoshi.floor());
}

String sendUsdInputTextForZatoshi(BigInt zatoshi, double zecUsdUnitPrice) {
  final usd = zatoshi.toDouble() / zatoshiPerZec.toDouble() * zecUsdUnitPrice;
  if (!usd.isFinite || usd <= 0) return '';
  return usd.toStringAsFixed(2);
}

String sendSendableUsdInputTextForZatoshi(
  BigInt zatoshi,
  double zecUsdUnitPrice,
) {
  final text = sendUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice);
  return text == '0.00' ? '' : text;
}

String sendUsdDisplayTextForZatoshi(BigInt zatoshi, double zecUsdUnitPrice) {
  final raw = sendUsdInputTextForZatoshi(zatoshi, zecUsdUnitPrice);
  if (raw.isEmpty) return '0.00';
  final parts = raw.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  final fraction = parts.length > 1 ? parts[1] : '00';
  return '${formatGroupedInteger(whole)}.$fraction';
}
