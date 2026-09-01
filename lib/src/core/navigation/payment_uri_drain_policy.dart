/// Pure routing policy for a parked ZIP-321 `zcash:` payment URI.
///
/// `_PaymentUriLinkListener` in `app.dart` parks an arriving payment URI in
/// `paymentUriPrefillProvider` and then asks this policy what to do with it.
/// Everything here is a plain function of the app's observable state so the
/// whole decision table can be unit-tested without a router, a wallet, or a
/// widget tree; `app.dart` only executes the returned action.
library;

import '../../features/swap/models/swap_activity_navigation.dart';

/// A parked prefill older than this is stale and is dropped instead of
/// delivered.
///
/// Without it, a link opened and then left parked (the user never unlocks, or
/// the wallet sits on an error screen) would fire as a payment on a much later,
/// unrelated wallet emission. `PaymentUriPrefillNotifier.takeIfFresh` enforces
/// the same age on the unlock-screen claim path.
const kPaymentUriParkTtl = Duration(minutes: 10);

/// Shown when the link cannot be opened at all: blocking storage failure or a
/// wallet load error.
const kPaymentUriUnavailableMessage = 'Payment link could not be opened.';

/// Shown when there is no wallet yet and the user is not already inside a
/// setup flow.
const kPaymentUriNoWalletMessage =
    'Set up or import a wallet before opening payment links.';

/// Shown when the link arrives while the user is part-way through onboarding,
/// import, or adding an account. Navigating away from those screens throws
/// away a typed seed phrase or a generated mnemonic, so the link is dropped
/// and the user is left exactly where they were.
const kPaymentUriOnboardingMessage =
    'Finish setting up your wallet before opening payment links.';

/// Shown when a send flow is already open.
const kPaymentUriSendInProgressMessage =
    'Finish or cancel your current send before opening another payment link.';

/// Shown for every other in-progress surface (signing, review, removal).
const kPaymentUriBusyMessage =
    'Finish or cancel what you are doing before opening a payment link.';

/// Shown when a Private (Ironwood) migration has the account's whole
/// spendable balance in flight, so the product disables sending entirely.
/// Delivering the link would open a send form that cannot be submitted.
const kPaymentUriMigrationSendGateMessage =
    'Finish the migration before opening payment links.';

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

  /// Drop the prefill without telling the user.
  dropSilently,

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

/// Whether [matchedLocation] belongs to onboarding, import, or add-account.
///
/// Shared with `appRedirect` so the router guard and the payment-URI drain
/// cannot drift apart. Covers both route trees: the desktop tree in `app.dart`
/// and `mobileOnboardingRoutes()` use the same paths on purpose.
bool isOnboardingLocation(String matchedLocation) =>
    matchedLocation == '/welcome' ||
    matchedLocation == '/add-account' ||
    matchedLocation.startsWith('/onboarding/') ||
    matchedLocation.startsWith('/import');

/// Locations that own the locked-wallet reset flow. A payment URI arriving
/// here must not navigate: `go('/unlock')` from `/lost-password` unmounts the
/// reset the user is part-way through (including while the Windows CredUI
/// prompt is up). The mobile forgot-passcode flow is a sheet over `/unlock`,
/// so it is covered by `/unlock` itself.
bool isUnlockFlowLocation(String matchedLocation) =>
    matchedLocation == '/unlock' || matchedLocation == '/lost-password';

/// Exact locations that would lose in-flight state if a payment URI navigated
/// away from them.
const _blockedExactLocations = <String>{
  // Swap / pay review and hardware signing.
  '/swap/review',
  '/swap/keystone-sign',
  '/pay/review',
  // Settings uninstall: its removing stage must not be interrupted.
  '/settings/uninstall',
  // Desktop wallet link: a live pairing-QR session that dies with the screen.
  '/settings/link-mobile',
  // Mobile shield flow.
  '/home/keystone-shield',
  // Voting hardware scan (desktop tree).
  '/voting/keystone/scan',
};

/// Migration locations that carry nothing in flight: the explainer steps a
/// user reads before choosing anything, and the terminal result screen.
///
/// Everything else under `/migration` is blocked by the subtree rule below,
/// so this allowlist is exact-match on purpose — a new migration route is
/// blocked until someone reads it and decides otherwise. `/migration` itself
/// stays out: on desktop it is a redirect resolver that immediately routes on
/// to `/migration/prepare` or the private status screen, so delivering there
/// would race its own `go()`.
const _migrationInformationalLocations = <String>{
  // Desktop `IronwoodMigrationFlowStep.intro` / mobile `_MobileMigrationIntro`.
  '/migration/intro',
  // Desktop howItWorks / mobile `_MobileMigrationHowItWorks`.
  '/migration/how-it-works',
  // Desktop whatToExpect (no mobile counterpart).
  '/migration/what-to-expect',
  // Mobile terminal result screen (no desktop counterpart).
  '/migration/complete',
};

/// The `/voting/poll/<roundId>/<step>` steps that must not be interrupted:
/// `review` builds the ballot, `status` drives the live submission job and
/// hosts the Keystone handoff.
const _blockedVotingSteps = <String>{'review', 'status'};

/// Which in-progress surface, if any, blocks payment-URI delivery at
/// [matchedLocation].
///
/// [queryParameters] are the current route's query parameters. They matter
/// because `matchedLocation` alone cannot tell a browsed swap activity detail
/// apart from the same screen opened to sign a ZEC deposit.
PaymentUriBlockedSurface paymentUriBlockedSurfaceAt(
  String matchedLocation, {
  Map<String, String> queryParameters = const {},
}) {
  if (_isInSubtree(matchedLocation, '/send')) {
    return PaymentUriBlockedSurface.send;
  }
  // The `/migration` subtree minus its explainer and result screens: the
  // Ironwood Keystone signing screens discard their pending Rust request in
  // `dispose()`, and the preparation/status/review screens hold live work.
  final inMigrationFlow =
      _isInSubtree(matchedLocation, '/migration') &&
      !_migrationInformationalLocations.contains(matchedLocation);
  if (inMigrationFlow ||
      _blockedExactLocations.contains(matchedLocation) ||
      _isBlockedVotingStep(matchedLocation) ||
      _isSwapDepositSigningLocation(matchedLocation, queryParameters)) {
    return PaymentUriBlockedSurface.other;
  }
  return PaymentUriBlockedSurface.none;
}

/// Whether a payment URI must be dropped rather than delivered at
/// [matchedLocation].
bool paymentUriBlockedAtLocation(
  String matchedLocation, {
  Map<String, String> queryParameters = const {},
}) =>
    paymentUriBlockedSurfaceAt(
      matchedLocation,
      queryParameters: queryParameters,
    ) !=
    PaymentUriBlockedSurface.none;

/// Whether a wallet emission is the reset transition — the wallet existed a
/// moment ago and does not any more (uninstall, lost-password reset).
///
/// A parked link must be dropped silently on that edge: draining it would
/// follow the wipe with a "Set up or import a wallet" snackbar and a jump to
/// `/welcome`, which reads as an error caused by the reset the user just
/// asked for.
///
/// [previousHasWallet] is null only when no wallet value has been observed
/// yet. That is not a reset, so it does not drop: the caller seeds the
/// baseline from the bootstrap snapshot precisely so a session that starts
/// locked (and therefore never emits before the reset) still sees `true` here.
bool paymentUriShouldDropOnWalletTransition({
  required bool? previousHasWallet,
  required bool hasWallet,
}) => previousHasWallet == true && !hasWallet;

bool _isInSubtree(String matchedLocation, String root) =>
    matchedLocation == root || matchedLocation.startsWith('$root/');

/// `/activity/swap/<id>?sign=<zecDeposit>`: the swap activity detail opened to
/// auto-sign the ZEC deposit. It drives the Keystone PCZT overlay, and its
/// `dispose()` throws the pending deposit draft away, so a payment URI must
/// not navigate off it. The same path without the query is just a receipt.
bool _isSwapDepositSigningLocation(
  String matchedLocation,
  Map<String, String> queryParameters,
) {
  if (queryParameters[swapActivitySignQueryKey] !=
      swapActivitySignZecDepositValue) {
    return false;
  }
  // ['', 'activity', 'swap', '<swapId>']
  final segments = matchedLocation.split('/');
  if (segments.length != 4) return false;
  if (segments[1] != 'activity' || segments[2] != 'swap') return false;
  return segments[3].isNotEmpty;
}

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
/// | parked longer than [kPaymentUriParkTtl]      | drop silently             |
/// | blocking storage failure / wallet error      | drop + unavailable msg    |
/// | wallet still loading                         | wait                      |
/// | `/welcome`, no wallet                        | drop + no-wallet msg      |
/// | onboarding / import / add-account location   | drop + onboarding msg     |
/// | other in-progress surface, or a busy overlay | drop + busy msg           |
/// | migration disables sending                   | drop + migration msg      |
/// | no wallet, anywhere else                     | `/welcome` + no-wallet msg|
/// | locked, already on `/unlock`/`/lost-password`| wait (stay parked)        |
/// | locked, anywhere else                        | `/unlock` (stay parked)   |
/// | unlocked but still on `/unlock`              | wait (unlock screen owns) |
/// | send flow open                               | drop + send msg           |
/// | otherwise                                    | deliver                   |
///
/// [parkedFor] is how long the prefill has been parked (null when nothing is
/// parked, or when the park time is unknown). [queryParameters] are the
/// current route's query parameters; they are what distinguishes a swap
/// activity detail being browsed from the same one signing a ZEC deposit. [sendStatusIsTerminal] is true
/// when the app is on `/send/status` and that send has already succeeded or
/// failed, which makes the status screen safe to leave. [hasBusySurface] is
/// true when an in-progress surface that owns no route of its own is mounted
/// — see `paymentUriBusySurfaceProvider`; it blocks exactly like
/// [PaymentUriBlockedSurface.other]. [sendGatedByMigration] is true when the
/// product disables sending because a Private migration holds the whole
/// spendable balance — see `migrationSendGateProvider`.
PaymentUriDrainDecision decidePaymentUriDrain({
  required bool hasParkedPrefill,
  required Duration? parkedFor,
  required bool hasBlockingFailure,
  required bool walletIsLoading,
  required bool walletHasError,
  required bool hasWallet,
  required bool isUnlocked,
  required String matchedLocation,
  Map<String, String> queryParameters = const {},
  bool sendStatusIsTerminal = false,
  bool hasBusySurface = false,
  bool sendGatedByMigration = false,
}) {
  if (!hasParkedPrefill) return _waitDecision;

  final blockedSurface = paymentUriBlockedSurfaceAt(
    matchedLocation,
    queryParameters: queryParameters,
  );

  // Age first: a link that has outlived its park window is dropped without a
  // message, whatever screen the app happens to be on.
  if (parkedFor != null && parkedFor > kPaymentUriParkTtl) {
    return const PaymentUriDrainDecision(PaymentUriDrainAction.dropSilently);
  }

  // A bootstrap retry rebuilds the ProviderScope and takes the parked prefill
  // with it, so staying silent here means the link disappears without the user
  // ever being told.
  if (hasBlockingFailure || walletHasError) {
    return const PaymentUriDrainDecision(
      PaymentUriDrainAction.dropWithMessage,
      message: kPaymentUriUnavailableMessage,
    );
  }

  // Wallet existence is not known yet; a later emission re-runs the drain.
  if (walletIsLoading) return _waitDecision;

  // Setup flows hold state that only lives in the widget tree (a typed seed
  // phrase, a freshly generated mnemonic, an in-flight account creation), so
  // never navigate out of them — with or without an existing wallet.
  if (isOnboardingLocation(matchedLocation)) {
    // On the welcome screen with no wallet nothing has been started yet, so
    // the plain no-wallet wording fits better than "finish setting up".
    return PaymentUriDrainDecision(
      PaymentUriDrainAction.dropWithMessage,
      message: matchedLocation == '/welcome' && !hasWallet
          ? kPaymentUriNoWalletMessage
          : kPaymentUriOnboardingMessage,
    );
  }

  // A non-send in-progress surface outranks the wallet-existence and lock rows.
  // The uninstall flow deliberately ends with hasWallet == false, so ordering
  // this after the no-wallet row would yank its removing/done stage to
  // /welcome. The send surfaces stay below: `/send*` is unreachable without a
  // wallet, and the terminal `/send/status` exception needs the delivery path.
  //
  // `hasBusySurface` joins this row rather than getting one of its own: an
  // overlay with no route of its own (the desktop Keystone shield signing
  // overlay on `/home`) is the same kind of in-flight work, and it outranks
  // the `/send*` rows below on purpose — while it is up, what is in flight is
  // the shield signing, not a send.
  if (blockedSurface == PaymentUriBlockedSurface.other || hasBusySurface) {
    return const PaymentUriDrainDecision(
      PaymentUriDrainAction.dropWithMessage,
      message: kPaymentUriBusyMessage,
    );
  }

  // Sits with the busy row for the same reason it outranks the wallet and
  // lock rows: the send form the link would open is one the product has
  // already taken away, so the user needs the migration explanation, not a
  // dead compose screen. Below the busy row, because an overlay actually in
  // flight is the more urgent thing to say.
  if (sendGatedByMigration) {
    return const PaymentUriDrainDecision(
      PaymentUriDrainAction.dropWithMessage,
      message: kPaymentUriMigrationSendGateMessage,
    );
  }

  if (!hasWallet) {
    return const PaymentUriDrainDecision(
      PaymentUriDrainAction.routeToWelcome,
      message: kPaymentUriNoWalletMessage,
    );
  }

  if (!isUnlocked) {
    // Already at the unlock/reset flow: leave it alone and keep the prefill
    // parked for the unlock screen to claim.
    if (isUnlockFlowLocation(matchedLocation)) return _waitDecision;
    return const PaymentUriDrainDecision(PaymentUriDrainAction.routeToUnlock);
  }

  // Unlocked but still on the unlock screen: the unlock flow's own claim owns
  // the navigation. Delivering here too would clobber it.
  if (matchedLocation == '/unlock') return _waitDecision;

  if (blockedSurface == PaymentUriBlockedSurface.send) {
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
  }

  return const PaymentUriDrainDecision(PaymentUriDrainAction.deliver);
}
