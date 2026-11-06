/// Mounts the payment-request card above the whole app.
///
/// A payment request is not a destination — it arrives over whatever the user
/// was already doing and asks one question. So the card is hosted once, at the
/// app level, above the router's content, rather than being a route of its own.
/// That is also what makes "the card stays until it is answered" true across a
/// route change. Mobile retains the closing card only for its exit transition.
library;

import 'dart:async';

import 'package:flutter/material.dart' show BottomSheet, Easing;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feedback/app_review.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/navigation/external_action_guard_provider.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/payment_request_flow_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../screens/mobile/mobile_send_screen.dart'
    show MobileSendReviewDraftArgs;
import '../services/payment_request_scanner.dart';
import '../services/send_flow.dart';
import 'payment_request_surface.dart';
import 'send_recipient_resolver.dart';

String _location(GoRouter router) => router.state.uri.path;

class PaymentRequestHost extends ConsumerStatefulWidget {
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
  ConsumerState<PaymentRequestHost> createState() => _PaymentRequestHostState();
}

class _PaymentRequestHostState extends ConsumerState<PaymentRequestHost>
    with SingleTickerProviderStateMixin {
  bool _scanning = false;
  bool _scanInFlight = false;
  late final _sheetController = BottomSheet.createAnimationController(this);
  late final _sheetAnimation = CurvedAnimation(
    parent: _sheetController,
    curve: Easing.legacyDecelerate,
  );
  PaymentRequestFlowState? _closingFlow;
  String? _presentedAccountUuid;
  GoRouter get router => widget.router;

  bool get _isMobile => kAppFormFactor == AppFormFactor.mobile;

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      ref.listenManual(paymentRequestFlowProvider, (previous, next) {
        if (next != null) {
          _presentedAccountUuid = ref
              .read(accountProvider)
              .value
              ?.activeAccountUuid;
          _closingFlow = null;
          _sheetController.forward();
        } else if (ref.read(appSecurityProvider).requiresUnlock ||
            ref.read(accountProvider).value?.activeAccountUuid !=
                _presentedAccountUuid) {
          _closingFlow = null;
          _sheetController.value = 0;
        } else {
          _closingFlow = previous;
          _sheetController.reverse().whenCompleteOrCancel(() {
            if (mounted && _sheetController.isDismissed) {
              setState(() => _closingFlow = null);
            }
          });
        }
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    if (_isMobile) {
      _sheetAnimation.dispose();
      _sheetController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeFlow = ref.watch(paymentRequestFlowProvider);
    if (_isMobile) {
      final requiresUnlock = ref.watch(
        appSecurityProvider.select((state) => state.requiresUnlock),
      );
      final accountUuid = ref.watch(
        accountProvider.select((state) => state.value?.activeAccountUuid),
      );
      // A dismissed flow no longer publishes updates. Its retained exit frame
      // must still disappear when the security or account context changes.
      if (requiresUnlock || accountUuid != _presentedAccountUuid) {
        _closingFlow = null;
      }
    }
    final flow =
        activeFlow ??
        (MediaQuery.disableAnimationsOf(context) ? null : _closingFlow);
    // [child] is the router's content, and it holds route-local state — a
    // half-typed Send form, a scroll offset, an expanded row. So it keeps one
    // position in the tree whether or not a card is up: always this `Stack`'s
    // first layer, with the request laid over it as a second layer. Handing it
    // to the surface as its background instead re-parented it on every show
    // and every dismiss, and Flutter answers a subtree that moved by disposing
    // and remounting it — which emptied the form the card was supposed to be
    // sitting harmlessly on top of.
    if (flow == null || _scanning) {
      return Stack(fit: StackFit.passthrough, children: [widget.child]);
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
    final spendableText = request.spendableText;
    final displayedRequest = spendableText == null
        ? request
        : request.withSpendableText(
            hideAmountIfPrivacyMode(
              spendableText,
              privacyModeEnabled: ref.watch(privacyModeProvider),
            ),
          );

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
        widget.child,
        _UnfocusWhenMounted(
          child: IgnorePointer(
            ignoring: activeFlow == null,
            child: PaymentRequestSurface.overlay(
              key: const ValueKey('payment_request_host_surface'),
              animation: _isMobile ? _sheetAnimation : null,
              cardKey: ValueKey(flow.prefill.id),
              request: displayedRequest,
              onContinue: _review,
              onEdit: _edit,
              onCancel: () {
                // A drag-dismiss animation can finish before the host rebuilds
                // for a newer link. Only the request that began closing may end.
                if (ref.read(paymentRequestFlowProvider)?.prefill.id ==
                    flow.prefill.id) {
                  notifier.dismiss();
                }
              },
              onRecheck: notifier.recheck,
              onScan: _scanOriginal,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _navigateAfterRelease(Future<void> Function() action) async {
    await ref
        .read(externalActionGuardProvider.notifier)
        .runNavigation(() => duringAppReviewBusy(ref, action));
  }

  Future<void> _edit() async {
    final notifier = ref.read(paymentRequestFlowProvider.notifier);
    // The card comes down at once, but the composer opens only when Rust
    // has released the card's proposal: the composer re-quotes the fee as
    // it mounts, and Rust cannot select inputs a proposal still holds, so a
    // wallet whose funds sit in those inputs would answer that quote with
    // "not enough ZEC" for the very payment the card just found affordable.
    // A slow release leaves the app usable underneath; a navigation made
    // meanwhile wins over the hand-back.
    final origin = _location(router);
    // The card clears before release completes. Keep reviews blocked through
    // that wait (including release retries) and the resulting navigation.
    await _navigateAfterRelease(() async {
      switch (await notifier.editHandingBack()) {
        case PaymentRequestEditReady(:final prefill):
          if (!mounted || _location(router) != origin) return;
          _releaseRetainedSendStatus(ref);
          // Both `/send` pages are keyed on the prefill's id, so this
          // remounts the composer and discards anything already typed
          // there. That is intended: Edit is the user asking for this
          // request to be loaded, and a composer that kept half of a
          // different payment's fields would be the more dangerous outcome
          // of the two.
          router.go('/send', extra: prefill);
        case PaymentRequestEditOvertaken():
          // A newer link owns the card now, and it carries the replaced
          // notice that accounts for this tap.
          break;
        case PaymentRequestEditUnavailable():
          break;
      }
    });
  }

  Future<void> _review() async {
    final flow = ref.read(paymentRequestFlowProvider);
    if (flow == null) return;
    final notifier = ref.read(paymentRequestFlowProvider.notifier);
    // An amount-less request has nothing to review: its primary action is
    // "Enter amount", which is Edit under a different label.
    if (!flow.canReview) {
      await _edit();
      return;
    }
    if (_isMobile) {
      // Mobile's review step owns proposal creation, so the proposal the
      // pre-check made would be a second one. Hand it back and give the
      // wizard the fee it already computed — but only navigate once it is
      // back: the review step re-quotes the fee as it mounts, and Rust
      // cannot select inputs a proposal still holds, so a wallet whose
      // funds sit in those inputs would answer that quote with "not enough
      // ZEC" for the very payment the card just found affordable.
      final origin = _location(router);
      await _navigateAfterRelease(() async {
        switch (await notifier.reviewHandingBack()) {
          case PaymentRequestReviewReady(:final args):
            if (!mounted || _location(router) != origin) return;
            _releaseRetainedSendStatus(ref);
            router.go('/send/review', extra: _mobileDraftFor(args));
          case PaymentRequestReviewOvertaken():
            // A newer link owns the card now, and it carries the replaced
            // notice that accounts for this tap. Opening the first
            // request's review under it would be a send the user did not
            // choose, behind a card they are about to dismiss.
            break;
          case PaymentRequestReviewUnavailable():
            break;
        }
      });
      return;
    }
    if (ref
        .read(externalActionGuardProvider)
        .blocks(ExternalAction.navigation)) {
      return;
    }
    final args = notifier.review();
    if (args == null) return;
    _releaseRetainedSendStatus(ref);
    router.go('/send/review', extra: args);
  }

  Future<void> _scanOriginal() async {
    if (!mounted) return;
    final original = ref.read(paymentRequestFlowProvider);
    final scanContext = router.routerDelegate.navigatorKey.currentContext;
    if (_scanInFlight ||
        original == null ||
        scanContext == null ||
        ref
            .read(externalActionGuardProvider)
            .blocks(ExternalAction.navigation)) {
      return;
    }
    final origin = _location(router);
    final network = ref.read(rpcEndpointProvider).networkName;
    final lease = ref.read(externalActionGuardProvider.notifier).acquire();
    _scanInFlight = true;
    setState(() => _scanning = true);
    try {
      // Keep the existing request/proposal owned by the flow. Cancellation
      // restores it; `present` serializes a successful replacement behind the
      // old proposal's release. OS requests wait behind this synchronous hold.
      final scanned = await ref.read(paymentRequestScannerProvider)(
        scanContext,
        router: router,
        networkName: network,
      );
      if (!mounted || scanned == null) return;
      final current = ref.read(paymentRequestFlowProvider);
      // Lock, reset, account changes or a newer request invalidate this scan.
      if (!identical(current?.prefill, original.prefill) ||
          ref.read(rpcEndpointProvider).networkName != network) {
        return;
      }
      if (_location(router) != origin) return;
      final check = ref
          .read(paymentRequestFlowProvider.notifier)
          .present(scanned, source: PaymentRequestSource.qrCode);
      // The camera is closed. Show the compact checking state while the old
      // proposal is released and the scanned request is checked.
      setState(() => _scanning = false);
      await check;
      // Keep the scanned terms in the payment-request surface. Review or
      // editing requires a separate choice after the user inspects them.
    } catch (_) {
      if (mounted &&
          scanContext.mounted &&
          identical(
            ref.read(paymentRequestFlowProvider)?.prefill,
            original.prefill,
          )) {
        showAppToast(
          scanContext,
          "Couldn't open the QR scanner. Try again.",
          iconName: AppIcons.warning,
        );
      }
    } finally {
      lease.release();
      _scanInFlight = false;
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Desktop `/send/review` takes a [SendReviewArgs] — a proposal that already
  /// exists. The mobile wizard's review step is a phase of the compose screen
  /// and creates its proposal on "Confirm & send", so its route extra is a
  /// draft instead. Handing mobile a draft keeps exactly one proposal alive at
  /// a time on either form factor.
  MobileSendReviewDraftArgs _mobileDraftFor(SendReviewArgs args) =>
      MobileSendReviewDraftArgs(
        sendFlowId: args.sendFlowId,
        recipient: args.address,
        addressType: args.addressType,
        // `activityDetail` keeps all 8 fraction digits and trims trailing
        // zeros, so this round-trips through `parseZecAmount` exactly.
        amountText: ZecAmount.fromZatoshi(
          args.amountZatoshi,
        ).activityDetail.amountText,
        feeZatoshi: args.feeZatoshi,
        memo: args.memo,
        preserveMemoWhitespace: args.memo != null,
        isPaymentRequest: args.isPaymentRequest,
        requestedBy: args.requestedBy,
        requestedAmountZatoshi: args.requestedAmountZatoshi,
      );

  /// A finished `/send/status` keeps its route payload retained so a router
  /// refresh can restore it. Navigating the card's answer onto `/send` or
  /// `/send/review` would let that stale receipt be restored over it.
  void _releaseRetainedSendStatus(WidgetRef ref) {
    ref.read(sendStatusRoutePayloadProvider.notifier).clear();
  }
}

/// A payment request takes input ownership from the screen underneath it.
/// Clearing that screen's focus also dismisses any native keyboard accessory
/// that UIKit renders above Flutter's widget tree.
class _UnfocusWhenMounted extends StatefulWidget {
  const _UnfocusWhenMounted({required this.child});

  final Widget child;

  @override
  State<_UnfocusWhenMounted> createState() => _UnfocusWhenMountedState();
}

class _UnfocusWhenMountedState extends State<_UnfocusWhenMounted> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
