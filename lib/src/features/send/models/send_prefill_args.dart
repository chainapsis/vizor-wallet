import '../../../core/zcash/zip321_payment_request.dart';

/// [SendPrefillArgs.source] for a prefill that came from a ZIP-321 payment
/// request (a `zcash:` link today, an in-app QR scan later). The send flow
/// reads it to keep the payment-request framing on the review screen.
const kPaymentUriPrefillSource = 'zcash-uri';

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

  /// The memo bytes a send built from this prefill will actually pay, or null
  /// when it will pay none.
  ///
  /// [memoText] is what the request carried; this is what survives
  /// [preserveMemoText]. One owner, because two of them read it: the
  /// pre-check proposes exactly these bytes, and the payment-request card
  /// displays exactly these bytes. A trim on one side and not the other would
  /// show the payer a memo the transaction does not pay.
  ///
  /// Whitespace-only survives when the request said to preserve it: those are
  /// real bytes the payment carries, so they are a memo, not an absence. The
  /// card is what has to make them visible.
  String? get outgoingMemoText {
    final raw = preserveMemoText ? memoText : memoText?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }
}

SendPrefillArgs sendPrefillArgsFromZip321Payment({
  required String id,
  required Zip321Payment payment,
}) {
  final message = payment.message;
  return SendPrefillArgs(
    id: id,
    source: kPaymentUriPrefillSource,
    address: payment.address,
    amountText: payment.amount,
    memoText: payment.memoText,
    preserveMemoText: payment.memoText != null,
    label: payment.label,
    // The parser screens `memo` for characters that can restyle the text
    // around them, but not `label` or `message`. The label is stripped where
    // it is sanitised; the message reaches the payment-request card with no
    // collapse and no clamp at all, so it is stripped here, at the boundary
    // where an untrusted request turns into something the wallet renders.
    message: message == null ? null : stripUnsupportedZip321MemoText(message),
  );
}
