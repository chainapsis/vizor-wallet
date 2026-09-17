import '../../../rust/api/wallet.dart' as rust_wallet;
import '../models/vizor_payment_link.dart';

/// Verify retained funding metadata before omitting the address from a compact
/// share. Conversion failures leave the durable record and its secret intact.
Future<Uri> preparePaymentLinkShareUri(
  VizorPaymentLink link, {
  bool compact = kPaymentLinkCompactSharing,
}) async {
  if (compact && link.knownAddress != null) {
    try {
      await rust_wallet.validateGiftAddress(
        mnemonic: link.mnemonic.trim(),
        network: link.network.trim(),
        address: link.address,
      );
    } catch (_) {
      throw const FormatException('Gift card address could not be verified.');
    }
  }
  return link.toShareUri(compact: compact);
}
