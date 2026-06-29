import '../../../core/zcash/zip321_payment_request.dart';

class SendPrefillArgs {
  const SendPrefillArgs({
    required this.id,
    required this.source,
    required this.address,
    this.amountText,
    this.memoText,
    this.preserveMemoText = false,
    this.label,
    this.message,
  });

  final String id;
  final String source;
  final String address;
  final String? amountText;
  final String? memoText;
  final bool preserveMemoText;
  final String? label;
  final String? message;

  String get fingerprint =>
      '$id|$address|${amountText ?? ''}|${memoText ?? ''}|$preserveMemoText';
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
    memoText: payment.memoText,
    preserveMemoText: payment.memoText != null,
    label: payment.label,
    message: payment.message,
  );
}
