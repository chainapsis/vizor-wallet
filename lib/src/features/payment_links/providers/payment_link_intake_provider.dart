import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vizor_payment_link.dart';

enum PaymentLinkIntakeResult { accepted, ignored, rejected }

/// The queue of Gift Card links that arrived but have not been opened yet.
///
/// **Deliberately not the same store as `paymentUriPrefillProvider`**, even
/// though both hold links delivered by the same native channel. A Gift Card is
/// a bearer claim on funds that are *not* in this wallet: losing one loses the
/// money, so up to [kPaymentLinkIntakeQueueCapacity] of them queue instead of
/// displacing each other, they never expire, and they survive a wallet reset —
/// the claim is still good on whatever wallet the user sets up next. A ZIP-321
/// request is the opposite on all three counts (one at a time, a 10-minute
/// TTL, dropped on reset) because it spends *this* wallet's money.

const kPaymentLinkIntakeQueueCapacity = 16;

class PaymentLinkIntakeState {
  const PaymentLinkIntakeState({
    this.pendingLinks = const [],
    this.errorMessage,
  });

  final List<VizorPaymentLink> pendingLinks;
  final String? errorMessage;

  VizorPaymentLink? get pendingLink =>
      pendingLinks.isEmpty ? null : pendingLinks.first;
}

class PaymentLinkIntakeNotifier extends Notifier<PaymentLinkIntakeState> {
  @override
  PaymentLinkIntakeState build() => const PaymentLinkIntakeState();

  PaymentLinkIntakeResult receive(String rawUri) {
    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null || !VizorPaymentLink.matchesEndpoint(uri)) {
      return PaymentLinkIntakeResult.ignored;
    }

    try {
      final link = VizorPaymentLink.parse(rawUri);
      final pendingLinks = state.pendingLinks;
      // Account and birthday identify a reusable claim wallet, not a duplicate
      // user intent. Only an identical versioned payload can be coalesced.
      final duplicate = pendingLinks.any(
        (pending) => pending.hasSameCanonicalPayload(link),
      );
      if (duplicate) {
        state = PaymentLinkIntakeState(pendingLinks: pendingLinks);
        return PaymentLinkIntakeResult.accepted;
      }
      if (pendingLinks.length >= kPaymentLinkIntakeQueueCapacity) {
        state = PaymentLinkIntakeState(
          pendingLinks: pendingLinks,
          errorMessage: 'Too many payment links are waiting to open.',
        );
        return PaymentLinkIntakeResult.rejected;
      }
      state = PaymentLinkIntakeState(pendingLinks: [...pendingLinks, link]);
      return PaymentLinkIntakeResult.accepted;
    } on FormatException {
      state = PaymentLinkIntakeState(
        pendingLinks: state.pendingLinks,
        errorMessage: 'Payment link could not be opened.',
      );
      return PaymentLinkIntakeResult.rejected;
    }
  }

  VizorPaymentLink? takePending() {
    final link = state.pendingLink;
    if (link == null) return null;
    state = PaymentLinkIntakeState(
      pendingLinks: state.pendingLinks.sublist(1),
      errorMessage: state.errorMessage,
    );
    return link;
  }

  void clearError() {
    state = PaymentLinkIntakeState(pendingLinks: state.pendingLinks);
  }
}

final paymentLinkIntakeProvider =
    NotifierProvider<PaymentLinkIntakeNotifier, PaymentLinkIntakeState>(
      PaymentLinkIntakeNotifier.new,
    );
