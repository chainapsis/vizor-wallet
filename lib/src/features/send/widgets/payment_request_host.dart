/// Mounts the payment-request card above the whole app.
///
/// A payment request is not a destination — it arrives over whatever the user
/// was already doing and asks one question. So the card is hosted once, at the
/// app level, above the router's content, rather than being a route of its own.
/// That is also what makes "the card stays until it is answered" true across a
/// route change, and what makes it disappear the instant
/// `paymentRequestFlowProvider` clears.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../providers/payment_request_flow_provider.dart';
import '../screens/mobile/mobile_send_screen.dart'
    show MobileSendReviewDraftArgs;
import '../services/payment_request_precheck.dart';
import '../services/send_flow.dart';
import 'payment_request_surface.dart';

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

  bool get _isMobile => kAppFormFactor == AppFormFactor.mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(paymentRequestFlowProvider);
    if (flow == null) return child;

    final notifier = ref.read(paymentRequestFlowProvider.notifier);

    void edit() {
      final prefill = notifier.edit();
      if (prefill == null) return;
      _releaseRetainedSendStatus(ref);
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
      if (_isMobile) {
        // Mobile's review step owns proposal creation, so the proposal the
        // pre-check made would be a second one. Hand it back and give the
        // wizard the fee it already computed.
        unawaited(
          PaymentRequestProposalHandle(
            reviewArgs: args,
            discardProposal: discardSendProposal,
          ).discard(logContext: 'PaymentRequest(mobile review handoff)'),
        );
        router.go('/send/review', extra: _mobileDraftFor(args));
        return;
      }
      router.go('/send/review', extra: args);
    }

    final surface = PaymentRequestSurface(
      key: const ValueKey('payment_request_host_surface'),
      request: flow.view,
      onContinue: review,
      onEdit: edit,
      onCancel: notifier.dismiss,
      background: child,
    );

    if (!_isMobile) return surface;

    // The card is not a route, so Android back would otherwise reach whatever
    // is underneath it. While a request is up, back answers the request.
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) notifier.dismiss();
      },
      child: surface,
    );
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
