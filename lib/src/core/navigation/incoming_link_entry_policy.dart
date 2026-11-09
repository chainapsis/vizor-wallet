import '../l10n/l10n.dart';
import 'app_route_predicates.dart';

enum IncomingLinkKind { home, giftCard, paymentRequest }

enum IncomingLinkEntryAction { open, wait, ignore }

class IncomingLinkEntryDecision {
  const IncomingLinkEntryDecision(this.action, {this.notice});

  final IncomingLinkEntryAction action;
  final IncomingLinkNotice? notice;
}

/// Why an unsolicited link was held back. Decisions carry the code; the toast
/// resolves it with the locale of the moment it is shown.
enum IncomingLinkNotice {
  homeBusy,
  homeSetup,
  giftBusy,
  giftSetup,
  paymentBusy;

  String text(AppLocalizations l10n) => switch (this) {
    homeBusy => l10n.incomingLinkHomeBusy,
    homeSetup => l10n.incomingLinkHomeSetup,
    giftBusy => l10n.incomingLinkGiftBusy,
    giftSetup => l10n.incomingLinkGiftSetup,
    paymentBusy => l10n.incomingLinkPaymentBusy,
  };
}

/// Navigation would discard input or an operation owned by these routes.
/// A payment card is an overlay, so it may still open over an ordinary form.
bool incomingLinkNavigationInterruptsTask(String location) =>
    isAccountSetupLocation(location) ||
    location == '/lost-password' ||
    isRouteOrChild(location, '/send') ||
    isRouteOrChild(location, '/swap') ||
    isRouteOrChild(location, '/pay') ||
    isRouteOrChild(location, '/migration') ||
    isRouteOrChild(location, '/home/keystone-shield') ||
    isRouteOrChild(location, '/home/ledger-shield') ||
    isRouteOrChild(location, '/home/shield') ||
    isRouteOrChild(location, '/voting/poll') ||
    isRouteOrChild(location, '/voting/keystone/scan') ||
    isRouteOrChild(location, '/settings/change-password') ||
    isRouteOrChild(location, '/settings/secret-passphrase') ||
    isRouteOrChild(location, '/settings/viewing-key') ||
    isRouteOrChild(location, '/settings/uninstall');

/// Only unsolicited incoming links consult this policy. Back, task completion
/// and security locking retain their own contracts. Product queues, expiry,
/// wallet availability and post-unlock delivery remain with their owners.
IncomingLinkEntryDecision decideIncomingLinkEntry({
  required IncomingLinkKind kind,
  required String location,
  bool locked = false,
  bool navigationBlocked = false,
  bool paymentRequestBlocked = false,
  bool paymentRequestPresented = false,
  bool activeSendProposal = false,
  bool sendInFlight = false,
}) {
  if (locked) {
    return IncomingLinkEntryDecision(
      kind == IncomingLinkKind.home
          ? IncomingLinkEntryAction.ignore
          : IncomingLinkEntryAction.wait,
    );
  }
  if (kind != IncomingLinkKind.paymentRequest &&
      isAccountSetupLocation(location)) {
    return IncomingLinkEntryDecision(
      kind == IncomingLinkKind.home
          ? IncomingLinkEntryAction.ignore
          : IncomingLinkEntryAction.wait,
      notice: kind == IncomingLinkKind.home
          ? IncomingLinkNotice.homeSetup
          : IncomingLinkNotice.giftSetup,
    );
  }
  final busy =
      navigationBlocked ||
      paymentRequestBlocked ||
      activeSendProposal ||
      (sendInFlight && location == '/send/status') ||
      (kind != IncomingLinkKind.paymentRequest &&
          (paymentRequestPresented ||
              incomingLinkNavigationInterruptsTask(location)));
  if (busy) {
    return IncomingLinkEntryDecision(
      kind == IncomingLinkKind.home
          ? IncomingLinkEntryAction.ignore
          : IncomingLinkEntryAction.wait,
      notice: switch (kind) {
        IncomingLinkKind.home => IncomingLinkNotice.homeBusy,
        IncomingLinkKind.giftCard => IncomingLinkNotice.giftBusy,
        IncomingLinkKind.paymentRequest => IncomingLinkNotice.paymentBusy,
      },
    );
  }
  return const IncomingLinkEntryDecision(IncomingLinkEntryAction.open);
}
