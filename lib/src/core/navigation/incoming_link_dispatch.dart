/// The single classifier for everything the native runners hand to Dart on
/// `com.zcash.wallet/payment_uri`.
///
/// Two products arrive on one pipe: ZIP-321 `zcash:` payment requests (all
/// five platforms) and Vizor Gift Card `https://` deeplinks (Android and iOS —
/// the desktop runners never register a handler for them). One classifier, one
/// subscription, so a link can only ever be handled by one of them.
///
/// **The host check runs before the scheme check, and that order is load
/// bearing.** A Gift Card link's fragment carries a 24-word mnemonic. Sending
/// it to `Zip321PaymentRequest.parse` would put fragments of that link into a
/// user-visible rejection message and into `log()`; testing the host first
/// means an `https://` link on the Vizor origin can never reach either. An
/// unrecognised path on that host classifies as [IncomingLinkUnknown], not as
/// a payment request.
///
/// [IncomingLinkUnknown] is silent by contract: the native side only forwards
/// links it already matched, so anything that lands here is a shape we do not
/// serve, and there is no user to apologise to.
library;

import 'vizor_deep_link.dart';

/// What an incoming link turned out to be.
sealed class IncomingLinkTarget {
  const IncomingLinkTarget();
}

/// A ZIP-321 `zcash:` payment request. [raw] is the trimmed link, still
/// unparsed — parsing stays with the payment-URI park/drain path so its two
/// rejection sentences keep living in one place.
final class IncomingPaymentRequestLink extends IncomingLinkTarget {
  const IncomingPaymentRequestLink(this.raw);

  final String raw;
}

/// A Vizor Gift Card link on the trusted deeplink origin.
final class IncomingGiftCardLink extends IncomingLinkTarget {
  const IncomingGiftCardLink(this.uri);

  final Uri uri;
}

/// The bare Vizor deeplink origin — "open the app", nothing more.
final class IncomingVizorHomeLink extends IncomingLinkTarget {
  const IncomingVizorHomeLink();
}

/// Not a shape this app serves. Dropped without a word.
final class IncomingLinkUnknown extends IncomingLinkTarget {
  const IncomingLinkUnknown();
}

const _zcashScheme = 'zcash';

/// Classifies [raw] into exactly one product's intake path.
///
/// See the library doc for why the host test comes first.
IncomingLinkTarget classifyIncomingLink(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);

  if (uri != null) {
    // Host first. Anything on the Vizor deeplink origin belongs to Gift Cards
    // and stops here, recognised path or not.
    switch (VizorDeepLink.routeFor(uri)) {
      case VizorDeepLinkRoute.home:
        return const IncomingVizorHomeLink();
      case VizorDeepLinkRoute.paymentLink:
        return IncomingGiftCardLink(uri);
      case null:
        if (VizorDeepLink.matchesOrigin(uri)) {
          return const IncomingLinkUnknown();
        }
    }

    if (uri.scheme.toLowerCase() == _zcashScheme) {
      return IncomingPaymentRequestLink(trimmed);
    }
    return const IncomingLinkUnknown();
  }

  // `Uri.tryParse` failing means the string is not a valid URI of any scheme,
  // so it cannot be a Gift Card link. A malformed `zcash:` link still has to
  // reach the payment-URI path, which is the only one that can tell the payer
  // their link is broken.
  return trimmed.toLowerCase().startsWith('$_zcashScheme:')
      ? IncomingPaymentRequestLink(trimmed)
      : const IncomingLinkUnknown();
}
