/// Where an incoming Gift Card link may open itself, and where it has to wait.
///
/// The mirror image of `payment_uri_drain_policy.dart`: that policy keeps a
/// ZIP-321 request from covering a Gift Card signing round, this one keeps a
/// Gift Card from navigating out from under a ZIP-321 request card. The two
/// products share one native pipe, so each has to yield to the other or
/// whichever link happens to arrive second wins by accident.
library;

import '../../../core/navigation/app_route_predicates.dart';

const kPaymentLinkDeferredByActiveFlowMessage =
    'Finish or cancel your current task to open this Gift Card.';
const kPaymentLinkDeferredByAccountSetupMessage =
    'Finish account setup to open this Gift Card.';

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
  // The onboarding/import/add-account set is the same one the payment-URI
  // drain drops on; `/import` covers `/import-keystone` and its children.
  if (isOnboardingLocation(matchedLocation)) {
    return kPaymentLinkDeferredByAccountSetupMessage;
  }
  // A live payment-request card is a task in progress even though it owns no
  // route, so it reads as one.
  if (paymentRequestCardPresented) {
    return kPaymentLinkDeferredByActiveFlowMessage;
  }
  if (matchedLocation == '/lost-password' ||
      isRouteOrChild(matchedLocation, '/send') ||
      isRouteOrChild(matchedLocation, '/swap') ||
      isRouteOrChild(matchedLocation, '/pay') ||
      isRouteOrChild(matchedLocation, '/migration') ||
      isRouteOrChild(matchedLocation, '/home/keystone-shield') ||
      isRouteOrChild(matchedLocation, '/voting/poll') ||
      isRouteOrChild(matchedLocation, '/voting/keystone/scan') ||
      isRouteOrChild(matchedLocation, '/settings/change-password') ||
      isRouteOrChild(matchedLocation, '/settings/secret-passphrase') ||
      isRouteOrChild(matchedLocation, '/settings/viewing-key') ||
      isRouteOrChild(matchedLocation, '/settings/uninstall')) {
    return kPaymentLinkDeferredByActiveFlowMessage;
  }
  return null;
}
