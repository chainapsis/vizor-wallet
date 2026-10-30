/// Where an incoming Gift Card link may open itself, and where it has to wait.
///
/// The mirror image of `payment_uri_drain_policy.dart`: that policy keeps a
/// ZIP-321 request from covering a Gift Card signing round, this one keeps a
/// Gift Card from navigating out from under a ZIP-321 request card. The two
/// products share one native pipe, so each has to yield to the other or
/// whichever link happens to arrive second wins by accident.
library;

import '../../../core/navigation/incoming_link_entry_policy.dart';

const kPaymentLinkDeferredByActiveFlowMessage = kIncomingGiftBusyMessage;
const kPaymentLinkDeferredByAccountSetupMessage = kIncomingGiftSetupMessage;

/// Routes whose in-progress user input or signing state must not be replaced
/// by an incoming Gift Card.
///
/// [paymentRequestCardPresented] is `paymentRequestFlowProvider` holding a
/// live ZIP-321 card. The card is a route-agnostic overlay, so no location
/// test can see it, and navigating to `/payment-links` underneath it would
/// tear down a payment the user was part-way through answering.
bool paymentLinkEntryBlockedAtLocation(
  String matchedLocation, {
  bool paymentRequestCardPresented = false,
}) {
  return paymentLinkEntryDeferredMessageAtLocation(
        matchedLocation,
        paymentRequestCardPresented: paymentRequestCardPresented,
      ) !=
      null;
}

String? paymentLinkEntryDeferredMessageAtLocation(
  String matchedLocation, {
  bool paymentRequestCardPresented = false,
}) {
  return decideIncomingLinkEntry(
    kind: IncomingLinkKind.giftCard,
    location: matchedLocation,
    paymentRequestPresented: paymentRequestCardPresented,
  ).message;
}
