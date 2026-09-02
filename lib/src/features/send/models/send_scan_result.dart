/// What a scan taken from inside the send flow turned out to be.
///
/// A camera has no idea what it is pointed at. Most of the time it is a bare
/// address and the composer just fills its recipient field. But a ZIP-321 QR
/// that already names an amount is the same object a `zcash:` link is, and
/// answering it in the send composer would throw away the framing the payment
/// request card exists to give it. So the send scanners classify first and let
/// the caller route: an address goes in the field, a request goes to the card.
///
/// Only the send-context scanners do this. Address book, swap and pay scan for
/// a destination, not for a payment to answer, so they stay address-only.
library;

import '../../../core/formatting/zec_amount.dart';
import '../../../core/zcash/zip321_payment_request.dart';
import '../../address_scan/domain/address_scan_payload.dart';
import 'send_prefill_args.dart';

/// A scan the send flow accepted.
sealed class SendScanResult {
  const SendScanResult();
}

/// Why a scanned ZIP-321 request came back as a bare recipient instead of a
/// request the card could answer.
///
/// A QR the parser refuses still surrenders its address, and the scan then
/// accepts that address on its own. That is the right recovery — the payer can
/// still pay — but it is not what they scanned, so the scanner names what was
/// left behind.
enum SendScanDowngrade {
  /// The request asked to pay more than one recipient. Only the first was
  /// taken; the others, and every amount, were dropped.
  multipleRecipients,

  /// The request carries a memo Vizor cannot read (binary, not text), so the
  /// reconciliation data the memo existed for is gone.
  unsupportedMemo,

  /// The request could not be read at all — bad encoding, a malformed amount,
  /// terms Vizor has no way to honour. Only the address survived.
  malformedRequest,
}

/// The one line the scanner shows for [downgrade], or null when nothing was
/// lost (a plain address QR, or a request whose address is all it asked for).
String? sendScanDowngradeMessage(SendScanDowngrade? downgrade) =>
    switch (downgrade) {
      SendScanDowngrade.multipleRecipients =>
        'Scanned the first recipient only — this request asks for more '
            'than one',
      SendScanDowngrade.unsupportedMemo =>
        "Scanned the address only — the request's message couldn't be "
            'read',
      SendScanDowngrade.malformedRequest =>
        "Scanned the address only — the payment request couldn't be read",
      null => null,
    };

/// A recipient and nothing else — today's behaviour, unchanged.
class SendScanAddress extends SendScanResult {
  const SendScanAddress(this.address, {this.downgrade});

  final String address;

  /// Set when this address is what is left of a payment request the scan could
  /// not answer. Null for a plain address QR: nothing was lost, so the scanner
  /// says nothing.
  final SendScanDowngrade? downgrade;
}

/// A ZIP-321 request carrying an amount, ready for the payment-request card.
class SendScanPaymentRequest extends SendScanResult {
  const SendScanPaymentRequest(this.prefill);

  final SendPrefillArgs prefill;
}

/// Makes each scanned request its own prefill, so a second scan of the same QR
/// is a new request rather than one the card can mistake for the parked one.
int _scanSequence = 0;

/// Classifies a raw scanned payload for a send-context scanner.
///
/// [acceptedAddress] is the address the scanner already normalized and
/// validated; passing it keeps the recipient the scanner said yes to rather
/// than re-deriving a possibly different one here.
///
/// Returns null when the payload yields no address at all.
SendScanResult? resolveSendScanPayload(String raw, {String? acceptedAddress}) {
  final resolved = _resolveZip321(raw);
  final payment = resolved.payment;
  if (payment != null) {
    return SendScanPaymentRequest(
      sendPrefillArgsFromZip321Payment(
        id: 'payment-qr-${++_scanSequence}',
        payment: payment,
      ),
    );
  }

  final address = (acceptedAddress ?? normalizeAddressScanPayload(raw))?.trim();
  if (address == null || address.isEmpty) return null;
  return SendScanAddress(address, downgrade: resolved.downgrade);
}

/// The single payment of a supported ZIP-321 request that names a positive
/// amount, or why the payload could not become one.
///
/// Everything without a payment falls through to the address-only path the
/// scanners already had. What changed is that the reasons are no longer all
/// the same silence: a request we refuse loses terms the payer scanned, while
/// a bare address or an amount-less request loses nothing the composer does
/// not ask for anyway.
({Zip321Payment? payment, SendScanDowngrade? downgrade}) _resolveZip321(
  String raw,
) {
  final Zip321PaymentRequest request;
  try {
    request = Zip321PaymentRequest.parse(raw);
  } on Zip321ParseException {
    // Only a `zcash:` payload had terms to lose. A bare address, or another
    // chain's URI, was never a payment request.
    return (
      payment: null,
      downgrade: _isZcashUri(raw) ? SendScanDowngrade.malformedRequest : null,
    );
  }
  if (!request.isSupported) {
    return (payment: null, downgrade: _refusedRequestDowngrade(request));
  }

  final payment = request.primaryPayment;
  final amount = parseZecAmount(payment.amount?.trim() ?? '');
  if (amount == null || amount <= BigInt.zero) {
    // An amount-less request has nothing the card can present that the
    // composer does not present better, and its address is what it asked to be
    // paid at. Nothing to report.
    return (payment: null, downgrade: null);
  }
  return (payment: payment, downgrade: null);
}

/// Why a parsed-but-refused request is a downgrade.
///
/// A custom-asset request is neither of the two named cases — it is readable
/// and single-recipient, Vizor just cannot pay in that asset — so it lands in
/// the catch-all rather than claiming its memo was unreadable.
SendScanDowngrade _refusedRequestDowngrade(Zip321PaymentRequest request) {
  if (request.payments.length > 1) return SendScanDowngrade.multipleRecipients;
  if (request.payments.any((payment) => payment.memoIsBinary)) {
    return SendScanDowngrade.unsupportedMemo;
  }
  return SendScanDowngrade.malformedRequest;
}

bool _isZcashUri(String raw) => raw.trim().toLowerCase().startsWith('zcash:');
