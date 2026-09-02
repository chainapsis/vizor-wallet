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

/// A recipient and nothing else — today's behaviour, unchanged.
class SendScanAddress extends SendScanResult {
  const SendScanAddress(this.address);

  final String address;
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
  final payment = _zip321PaymentWithAmount(raw);
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
  return SendScanAddress(address);
}

/// The single payment of a supported ZIP-321 request that names a positive
/// amount, or null for anything else.
///
/// Everything else — a bare address, a request we refuse (multiple payments, a
/// binary memo), an amount-less request — falls through to the address-only
/// path the scanners already had. An amount-less request has nothing the card
/// can present that the composer does not present better.
Zip321Payment? _zip321PaymentWithAmount(String raw) {
  final Zip321PaymentRequest request;
  try {
    request = Zip321PaymentRequest.parse(raw);
  } on Zip321ParseException {
    return null;
  }
  if (!request.isSupported) return null;

  final payment = request.primaryPayment;
  final amount = parseZecAmount(payment.amount?.trim() ?? '');
  if (amount == null || amount <= BigInt.zero) return null;
  return payment;
}
