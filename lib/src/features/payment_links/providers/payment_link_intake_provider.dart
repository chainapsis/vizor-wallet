import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vizor_payment_link.dart';

enum PaymentLinkIntakeResult { accepted, ignored, rejected }

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

  PaymentLinkIntakeResult ingest(String rawUri) {
    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null || uri.scheme.toLowerCase() != VizorPaymentLink.scheme) {
      return PaymentLinkIntakeResult.ignored;
    }

    try {
      final link = VizorPaymentLink.decode(rawUri);
      state = PaymentLinkIntakeState(
        pendingLinks: [...state.pendingLinks, link],
      );
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
