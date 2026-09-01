/// Pure routing policy for a parked ZIP-321 `zcash:` payment URI.
///
/// `_PaymentUriLinkListener` in `app.dart` parks an arriving payment URI in
/// `paymentUriPrefillProvider` and then asks this policy what to do with it.
/// Everything here is a plain function of the app's observable state so the
/// whole decision table can be unit-tested without a router, a wallet, or a
/// widget tree; `app.dart` only executes the returned action.
library;

/// Shown when there is no wallet yet.
const kPaymentUriNoWalletMessage =
    'Set up or import a wallet before opening payment links.';

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

/// What `_drainPendingPrefill` should do with the parked prefill.
enum PaymentUriDrainAction {
  /// Leave the prefill parked and do nothing. Something else (the unlock
  /// screen, a later wallet emission) still owns it.
  wait,

  /// Drop the prefill and show [PaymentUriDrainDecision.message].
  dropWithMessage,

  /// Leave the prefill parked and route to `/unlock`; the unlock flow claims
  /// it after a successful unlock.
  routeToUnlock,

  /// Drop the prefill, route to `/welcome`, and show the message.
  routeToWelcome,

  /// Clear the prefill and hand it to `/send`.
  deliver,
}

/// The action plus everything needed to execute it.
class PaymentUriDrainDecision {
  const PaymentUriDrainDecision(
    this.action, {
    this.message,
    this.clearSendStatusPayload = false,
  });

  final PaymentUriDrainAction action;

  /// Snackbar text, when the action carries one.
  final String? message;

  /// Set when delivery leaves a finished `/send/status` behind: its retained
  /// route payload must be released so the status route cannot be restored
  /// over the newly delivered send.
  final bool clearSendStatusPayload;

  @override
  String toString() =>
      'PaymentUriDrainDecision($action, message: $message, '
      'clearSendStatusPayload: $clearSendStatusPayload)';
}

const _waitDecision = PaymentUriDrainDecision(PaymentUriDrainAction.wait);

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

/// Decides what to do with the parked payment-URI prefill.
///
/// The rows, in order:
///
/// | condition                                   | action                    |
/// |---------------------------------------------|---------------------------|
/// | nothing parked                              | wait                      |
/// | blocking storage failure / wallet error      | wait                      |
/// | wallet still loading                         | wait                      |
/// | no wallet                                    | `/welcome` + no-wallet msg|
/// | locked                                       | `/unlock` (stay parked)   |
/// | unlocked but still on `/unlock`              | wait (unlock screen owns) |
/// | send flow open                               | drop + send msg           |
/// | other in-progress surface                    | drop + busy msg           |
/// | otherwise                                    | deliver                   |
///
/// [sendStatusIsTerminal] is true when the app is on `/send/status` and that
/// send has already succeeded or failed, which makes the status screen safe to
/// leave.
PaymentUriDrainDecision decidePaymentUriDrain({
  required bool hasParkedPrefill,
  required bool hasBlockingFailure,
  required bool walletIsLoading,
  required bool walletHasError,
  required bool hasWallet,
  required bool isUnlocked,
  required String matchedLocation,
  bool sendStatusIsTerminal = false,
}) {
  if (!hasParkedPrefill) return _waitDecision;

  if (hasBlockingFailure || walletHasError) return _waitDecision;

  // Wallet existence is not known yet; a later emission re-runs the drain.
  if (walletIsLoading) return _waitDecision;

  if (!hasWallet) {
    return const PaymentUriDrainDecision(
      PaymentUriDrainAction.routeToWelcome,
      message: kPaymentUriNoWalletMessage,
    );
  }

  if (!isUnlocked) {
    return const PaymentUriDrainDecision(PaymentUriDrainAction.routeToUnlock);
  }

  // Unlocked but still on the unlock screen: the unlock flow's own claim owns
  // the navigation. Delivering here too would clobber it.
  if (matchedLocation == '/unlock') return _waitDecision;

  switch (paymentUriBlockedSurfaceAt(matchedLocation)) {
    case PaymentUriBlockedSurface.send:
      // A finished send status screen has nothing left to lose; release its
      // retained route payload and deliver.
      if (matchedLocation == '/send/status' && sendStatusIsTerminal) {
        return const PaymentUriDrainDecision(
          PaymentUriDrainAction.deliver,
          clearSendStatusPayload: true,
        );
      }
      return const PaymentUriDrainDecision(
        PaymentUriDrainAction.dropWithMessage,
        message: kPaymentUriSendInProgressMessage,
      );
    case PaymentUriBlockedSurface.other:
      return const PaymentUriDrainDecision(
        PaymentUriDrainAction.dropWithMessage,
        message: kPaymentUriBusyMessage,
      );
    case PaymentUriBlockedSurface.none:
      return const PaymentUriDrainDecision(PaymentUriDrainAction.deliver);
  }
}
