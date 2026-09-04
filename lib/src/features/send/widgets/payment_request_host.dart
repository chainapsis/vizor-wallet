/// Mounts the payment-request card above the whole app.
///
/// A payment request is not a destination — it arrives over whatever the user
/// was already doing and asks one question. So the card is hosted once, at the
/// app level, above the router's content, rather than being a route of its own.
/// That is also what makes "the card stays until it is answered" true across a
/// route change, and what makes it disappear the instant
/// `paymentRequestFlowProvider` clears.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/account_models.dart';
import '../../../providers/payment_request_flow_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../services/send_flow.dart';
import 'payment_request_surface.dart';
import 'send_recipient_resolver.dart';

class PaymentRequestHost extends ConsumerWidget {
  const PaymentRequestHost({
    required this.router,
    required this.child,
    super.key,
  });

  /// Passed in rather than looked up: the host is mounted from
  /// `MaterialApp.router`'s `builder`, whose context sits *above* the
  /// `Router`, so `GoRouter.of(context)` finds nothing there.
  final GoRouter router;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(paymentRequestFlowProvider);
    // [child] is the router's content, and it holds route-local state — a
    // half-typed Send form, a scroll offset, an expanded row. So it keeps one
    // position in the tree whether or not a card is up: always this `Stack`'s
    // first layer, with the request laid over it as a second layer. Handing it
    // to the surface as its background instead re-parented it on every show
    // and every dismiss, and Flutter answers a subtree that moved by disposing
    // and remounting it — which emptied the form the card was supposed to be
    // sitting harmlessly on top of.
    if (flow == null) {
      return Stack(fit: StackFit.passthrough, children: [child]);
    }

    final notifier = ref.read(paymentRequestFlowProvider.notifier);

    // Who the request is actually addressed to, when the wallet can say. Both
    // sources load asynchronously and are read for their settled value only:
    // an address book still reading from secure storage, or an own-account
    // lookup still asking Rust for each account's addresses, leaves the card
    // showing the plain address until it lands rather than holding the card
    // back. These are watched below the early return above, so a wallet with
    // no request on screen never pays for the lookup.
    final contacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    // Same story for the price: `zecHomeUsdUnitPriceProvider` is autoDispose
    // and its market data fills asynchronously, so a request that arrives over
    // Settings or Activity — screens that subscribe to neither — would read
    // null once and never show a fiat line, while the same request opened from
    // Home would. Watching it here both keeps it alive for the card's lifetime
    // and re-applies the value when it lands.
    final zecUsdUnitPrice = ref.watch(zecHomeUsdUnitPriceProvider);
    final request = flow.view
        .withRecipientIdentity(
          paymentRequestRecipientIdentityFor(
            contacts: contacts,
            address: flow.view.address,
            ownAccounts: ownAccounts,
          ),
        )
        .withFiatText(
          paymentRequestFiatText(
            prefill: flow.prefill,
            zecUsdUnitPrice: zecUsdUnitPrice,
          ),
        );

    void edit() {
      final prefill = notifier.edit();
      if (prefill == null) return;
      _releaseRetainedSendStatus(ref);
      // Both `/send` pages are keyed on the prefill's id, so this remounts the
      // composer and discards anything already typed there. That is intended:
      // Edit is the user asking for this request to be loaded, and a composer
      // that kept half of a different payment's fields would be the more
      // dangerous outcome of the two.
      router.go('/send', extra: prefill);
    }

    void review() {
      // An amount-less request has nothing to review: its primary action is
      // "Enter amount", which is Edit under a different label.
      if (!flow.canReview) {
        edit();
        return;
      }
      final args = notifier.review();
      if (args == null) return;
      _releaseRetainedSendStatus(ref);
      router.go('/send/review', extra: args);
    }

    // The Android system back press is answered by
    // `MobileExitBackDispatcher.handleBackAboveRouter`, not by a `PopScope`
    // here: this host is mounted from `MaterialApp.router`'s builder, above
    // the `Router`, and a `PopScope` with no `ModalRoute` ancestor never runs.
    // Pointer-driven dismissal (the scrim, the ⨯, and — because the scrim is
    // an opaque hit-test target over the whole app — the iOS edge swipe) is
    // owned by `PaymentRequestSurface`.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        PaymentRequestSurface.overlay(
          key: const ValueKey('payment_request_host_surface'),
          cardKey: ValueKey(flow.prefill.id),
          request: request,
          onContinue: review,
          onEdit: edit,
          onCancel: notifier.dismiss,
          onRecheck: notifier.recheck,
        ),
      ],
    );
  }

  /// A finished `/send/status` keeps its route payload retained so a router
  /// refresh can restore it. Navigating the card's answer onto `/send` or
  /// `/send/review` would let that stale receipt be restored over it.
  void _releaseRetainedSendStatus(WidgetRef ref) {
    ref.read(sendStatusRoutePayloadProvider.notifier).clear();
  }
}
