import '../../../core/l10n/l10n.dart';
import 'vizor_payment_link.dart';

/// Why a scanned QR code cannot be opened as a Gift Card.
enum PaymentLinkQrIssue { notGiftCard, otherNetwork }

/// A scanned code that is not a Gift Card for this wallet. The English
/// message is for logs; screens show [paymentLinkQrIssueText].
class PaymentLinkQrException extends FormatException {
  const PaymentLinkQrException(this.issue, super.message);

  final PaymentLinkQrIssue issue;
}

String paymentLinkQrIssueText(
  AppLocalizations l10n,
  PaymentLinkQrIssue issue,
) => switch (issue) {
  PaymentLinkQrIssue.notGiftCard => l10n.paymentLinkScanNotGiftCard,
  PaymentLinkQrIssue.otherNetwork => l10n.paymentLinkScanOtherNetwork,
};

VizorPaymentLink decodePaymentLinkQr(
  String raw, {
  required String networkName,
}) {
  final VizorPaymentLink link;
  try {
    link = VizorPaymentLink.parse(raw);
  } on FormatException {
    throw const PaymentLinkQrException(
      PaymentLinkQrIssue.notGiftCard,
      "This isn't a gift card QR code.",
    );
  }
  if (link.network != networkName) {
    throw const PaymentLinkQrException(
      PaymentLinkQrIssue.otherNetwork,
      'This gift card is for a different network.',
    );
  }
  return link;
}
