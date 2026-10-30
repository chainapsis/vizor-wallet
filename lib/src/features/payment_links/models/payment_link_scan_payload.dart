import 'vizor_payment_link.dart';

VizorPaymentLink decodePaymentLinkQr(
  String raw, {
  required String networkName,
}) {
  final VizorPaymentLink link;
  try {
    link = VizorPaymentLink.parse(raw);
  } on FormatException {
    throw const FormatException("This isn't a gift card QR code.");
  }
  if (link.network != networkName) {
    throw const FormatException('This gift card is for a different network.');
  }
  return link;
}
