/// Pure routing policy for a parked ZIP-321 `zcash:` payment URI.
///
/// `_PaymentUriLinkListener` in `app.dart` parks an arriving payment URI in
/// `paymentUriPrefillProvider` and then asks this policy what to do with it.
/// Everything here is a plain function of the app's observable state so the
/// whole decision table can be unit-tested without a router, a wallet, or a
/// widget tree; `app.dart` only executes the returned action.
///
/// The policy no longer blocks on where the user happens to be. A delivered
/// request is presented as a card over the current screen rather than a jump
/// to `/send`, so there is nothing to interrupt: the swap review, the migration
/// steps and a send already in progress all stay exactly where they were until
/// the user answers the card. The rows that remain are the ones about whether
/// the request can be shown at all — no wallet, mid-onboarding, locked, stale,
/// or a wallet that failed to load.
library;

import '../zcash/zip321_payment_request.dart';

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
///
/// It does not name a cause. A blocking failure is one of several things (a
/// locked keyring, a failed DB migration), and `/storage-unavailable` already
/// states the one that happened and offers Retry. What the payer needs here is
/// the one thing that is always true: the link is gone, and re-opening it once
/// the wallet is up recovers it.
const kPaymentUriUnavailableMessage =
    "Vizor couldn't open this payment link. "
    'Open it again once your wallet has loaded.';

/// Shown when a second `zcash:` link arrives before the first one has been
/// delivered or claimed. The prefill holds one link at a time (latest wins,
/// no queue), so the earlier one is gone and the user is told rather than
/// left to wonder which link opened.
const kPaymentUriReplacedMessage =
    'Only the newest payment link was kept. Open the earlier one again to '
    'pay it.';

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

/// Shown when a Private (Ironwood) migration has the account's whole
/// spendable balance in flight, so the product disables sending entirely.
/// Delivering the link would open a send form that cannot be submitted.
const kPaymentUriMigrationSendGateMessage =
    'Finish your Ironwood migration before opening payment links.';

/// Shown when a `zcash:` link parses but asks for a ZIP-321 feature Vizor does
/// not implement yet: more than one recipient, a binary memo, a custom asset.
/// Nothing about the link is wrong, so it does not tell the sender off.
const kPaymentUriUnsupportedMessage =
    "This payment link uses a feature Vizor doesn't support yet.";

/// Shown when a `zcash:` link cannot be parsed at all — bad encoding, a
/// malformed amount, a missing address, a link too long to read.
///
/// The parser's own message is spec wording written for us, not for the payer,
/// and it echoes back fragments of the link's own text; it belongs in the log.
const kPaymentUriMalformedMessage =
    "This payment link isn't valid. Ask the sender for a new one.";

/// The one sentence the payer sees when a `zcash:` link is refused.
///
/// Two buckets, because only two answers differ for the user: wait for Vizor
/// to support the feature, or ask the sender for a link that works.
/// [Zip321UnsupportedRequestException] carries the first, every other rejection
/// the second.
String paymentUriRejectionMessage(Object error) =>
    error is Zip321UnsupportedRequestException
    ? kPaymentUriUnsupportedMessage
    : kPaymentUriMalformedMessage;

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

  /// Clear the prefill and present it as a payment-request card.
  deliver,
}

/// The action plus everything needed to execute it.
class PaymentUriDrainDecision {
  const PaymentUriDrainDecision(this.action, {this.message});

  final PaymentUriDrainAction action;

  /// Snackbar text, when the action carries one.
  final String? message;

  @override
  String toString() => 'PaymentUriDrainDecision($action, message: $message)';
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
/// | a busy overlay is up                         | wait (present when it goes)|
/// | migration disables sending                   | drop + migration msg      |
/// | no wallet, anywhere else                     | `/welcome` + no-wallet msg|
/// | locked, already on `/unlock`/`/lost-password`| wait (stay parked)        |
/// | locked, anywhere else                        | `/unlock` (stay parked)   |
/// | unlocked but still on `/unlock`              | wait (unlock screen owns) |
/// | otherwise                                    | present the card          |
///
/// [parkedFor] is how long the prefill has been parked (null when nothing is
/// parked, or when the park time is unknown). [hasBusySurface] is true while a
/// hardware signing session is mounted — see `paymentUriBusySurfaceProvider`.
/// [sendGatedByMigration] is true when the product disables sending because a
/// Private migration holds the whole spendable balance — see
/// `migrationSendGateProvider`.
PaymentUriDrainDecision decidePaymentUriDrain({
  required bool hasParkedPrefill,
  required Duration? parkedFor,
  required bool hasBlockingFailure,
  required bool walletIsLoading,
  required bool walletHasError,
  required bool hasWallet,
  required bool isUnlocked,
  required String matchedLocation,
  bool hasBusySurface = false,
  bool sendGatedByMigration = false,
}) {
  if (!hasParkedPrefill) return _waitDecision;

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
  // phrase, a freshly generated mnemonic, an in-flight account creation).
  // A card over a half-typed seed phrase is the one presentation that would
  // still cost the user something, so onboarding keeps its drop.
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

  // A hardware signing session waits rather than drops. The device is showing
  // a QR the user is part-way through scanning, so a card over it would be
  // both a distraction and, on the desktop shield overlay, a scrim over a
  // live animated QR. The listener re-drains when the hold is given back, and
  // the TTL still bounds the wait.
  if (hasBusySurface) return _waitDecision;

  // The send the card offers is one the product has already taken away, so
  // the user needs the migration explanation rather than a card whose Review
  // and Edit both lead nowhere.
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
  // the handoff. Presenting here too would race it.
  if (matchedLocation == '/unlock') return _waitDecision;

  return const PaymentUriDrainDecision(PaymentUriDrainAction.deliver);
}
