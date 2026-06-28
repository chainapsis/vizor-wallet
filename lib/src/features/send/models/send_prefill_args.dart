import '../../../core/zcash/zip321_payment_request.dart';

class SendPrefillArgs {
  const SendPrefillArgs({
    required this.id,
    required this.source,
    required this.address,
    this.amountText,
    this.memoText,
    this.label,
    this.message,
  });

  final String id;
  final String source;
  final String address;
  final String? amountText;
  final String? memoText;
  final String? label;
  final String? message;

  String get fingerprint =>
      '$id|$address|${amountText ?? ''}|${memoText ?? ''}';
}

SendPrefillArgs sendPrefillArgsFromZip321Payment({
  required String id,
  required Zip321Payment payment,
}) {
  return SendPrefillArgs(
    id: id,
    source: 'zcash-uri',
    address: payment.address,
    amountText: payment.amount,
    memoText: payment.memoText == null
        ? null
        : sanitizePaymentUriMemoText(payment.memoText!),
    label: payment.label,
    message: payment.message,
  );
}

String sanitizePaymentUriMemoText(String value) {
  return String.fromCharCodes(
    value.runes.where((codePoint) => !_isUnsafeDisplayControl(codePoint)),
  );
}

bool _isUnsafeDisplayControl(int codePoint) {
  if (_bidiControlCodePoints.contains(codePoint)) return true;
  if (codePoint < 0x20) {
    return codePoint != 0x09 && codePoint != 0x0A && codePoint != 0x0D;
  }
  return codePoint >= 0x7F && codePoint <= 0x9F;
}

const _bidiControlCodePoints = <int>{
  0x061C,
  0x200E,
  0x200F,
  0x202A,
  0x202B,
  0x202C,
  0x202D,
  0x202E,
  0x2066,
  0x2067,
  0x2068,
  0x2069,
};
