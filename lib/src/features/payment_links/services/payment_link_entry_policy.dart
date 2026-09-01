const kPaymentLinkDeferredByActiveFlowMessage =
    'Finish or cancel your current task to open this Gift Card.';
const kPaymentLinkDeferredByAccountSetupMessage =
    'Finish account setup to open this Gift Card.';

/// Routes whose in-progress user input or signing state must not be replaced
/// by an incoming Gift Card.
bool paymentLinkEntryBlockedAtLocation(String matchedLocation) {
  return paymentLinkEntryDeferredMessageAtLocation(matchedLocation) != null;
}

String? paymentLinkEntryDeferredMessageAtLocation(String matchedLocation) {
  if (matchedLocation == '/welcome' ||
      matchedLocation == '/add-account' ||
      matchedLocation.startsWith('/onboarding/') ||
      _isRouteOrChild(matchedLocation, '/import') ||
      _isRouteOrChild(matchedLocation, '/import-keystone')) {
    return kPaymentLinkDeferredByAccountSetupMessage;
  }
  if (matchedLocation == '/lost-password' ||
      _isRouteOrChild(matchedLocation, '/send') ||
      _isRouteOrChild(matchedLocation, '/swap') ||
      _isRouteOrChild(matchedLocation, '/pay') ||
      _isRouteOrChild(matchedLocation, '/migration') ||
      _isRouteOrChild(matchedLocation, '/home/keystone-shield') ||
      _isRouteOrChild(matchedLocation, '/voting/poll') ||
      _isRouteOrChild(matchedLocation, '/voting/keystone/scan') ||
      _isRouteOrChild(matchedLocation, '/settings/change-password') ||
      _isRouteOrChild(matchedLocation, '/settings/secret-passphrase') ||
      _isRouteOrChild(matchedLocation, '/settings/viewing-key') ||
      _isRouteOrChild(matchedLocation, '/settings/uninstall')) {
    return kPaymentLinkDeferredByActiveFlowMessage;
  }
  return null;
}

bool _isRouteOrChild(String matchedLocation, String routePath) {
  return matchedLocation == routePath ||
      matchedLocation.startsWith('$routePath/');
}
