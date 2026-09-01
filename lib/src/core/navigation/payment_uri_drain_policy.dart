/// Pure routing policy for a parked ZIP-321 `zcash:` payment URI.
///
/// `_PaymentUriLinkListener` in `app.dart` parks an arriving payment URI in
/// `paymentUriPrefillProvider` and then asks this policy what to do with it.
/// Everything here is a plain function of the app's observable state so the
/// whole decision table can be unit-tested without a router, a wallet, or a
/// widget tree; `app.dart` only executes the returned action.
library;

/// Shown when a send flow is already open.
const kPaymentUriSendInProgressMessage =
    'Finish or cancel your current send before opening another payment link.';

/// Shown for every other in-progress surface (signing, review, removal).
const kPaymentUriBusyMessage =
    'Finish or cancel what you are doing before opening a payment link.';

/// The kind of in-progress surface occupying a location, if any.
enum PaymentUriBlockedSurface {
  /// Payment-URI delivery is allowed here.
  none,

  /// An active send flow. Keeps its own, more specific message.
  send,

  /// Another surface that would lose in-flight state if we navigated away:
  /// swap/pay review and signing, the Ironwood migration flow, voting
  /// review/submission, the uninstall flow, the mobile shield flow.
  other,
}

/// Exact locations that would lose in-flight state if a payment URI navigated
/// away from them.
const _blockedExactLocations = <String>{
  // Swap / pay review and hardware signing.
  '/swap/review',
  '/swap/keystone-sign',
  '/pay/review',
  // Settings uninstall: its removing stage must not be interrupted.
  '/settings/uninstall',
  // Mobile shield flow.
  '/home/keystone-shield',
  // Voting hardware scan (desktop tree).
  '/voting/keystone/scan',
};

/// The `/voting/poll/<roundId>/<step>` steps that must not be interrupted:
/// `review` builds the ballot, `status` drives the live submission job and
/// hosts the Keystone handoff.
const _blockedVotingSteps = <String>{'review', 'status'};

/// Which in-progress surface, if any, blocks payment-URI delivery at
/// [matchedLocation].
PaymentUriBlockedSurface paymentUriBlockedSurfaceAt(String matchedLocation) {
  if (_isInSubtree(matchedLocation, '/send')) {
    return PaymentUriBlockedSurface.send;
  }
  // The whole `/migration` subtree: the Ironwood Keystone signing screens
  // discard their pending Rust request in `dispose()`.
  if (_isInSubtree(matchedLocation, '/migration') ||
      _blockedExactLocations.contains(matchedLocation) ||
      _isBlockedVotingStep(matchedLocation)) {
    return PaymentUriBlockedSurface.other;
  }
  return PaymentUriBlockedSurface.none;
}

/// Whether a payment URI must be dropped rather than delivered at
/// [matchedLocation].
bool paymentUriBlockedAtLocation(String matchedLocation) =>
    paymentUriBlockedSurfaceAt(matchedLocation) !=
    PaymentUriBlockedSurface.none;

bool _isInSubtree(String matchedLocation, String root) =>
    matchedLocation == root || matchedLocation.startsWith('$root/');

bool _isBlockedVotingStep(String matchedLocation) {
  // ['', 'voting', 'poll', '<roundId>', '<step>']
  final segments = matchedLocation.split('/');
  if (segments.length != 5) return false;
  if (segments[1] != 'voting' || segments[2] != 'poll') return false;
  if (segments[3].isEmpty) return false;
  return _blockedVotingSteps.contains(segments[4]);
}
