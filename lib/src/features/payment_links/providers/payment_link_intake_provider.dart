import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vizor_payment_link.dart';

enum PaymentLinkIntakeResult { accepted, ignored, rejected }

class PaymentLinkIntakeState {
  const PaymentLinkIntakeState({this.pendingLink, this.errorMessage});

  final VizorPaymentLink? pendingLink;
  final String? errorMessage;
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
      state = PaymentLinkIntakeState(pendingLink: link);
      return PaymentLinkIntakeResult.accepted;
    } on FormatException {
      state = PaymentLinkIntakeState(
        pendingLink: state.pendingLink,
        errorMessage: 'Payment link could not be opened.',
      );
      return PaymentLinkIntakeResult.rejected;
    }
  }

  VizorPaymentLink? takePending() {
    final link = state.pendingLink;
    state = PaymentLinkIntakeState(errorMessage: state.errorMessage);
    return link;
  }

  void clearError() {
    state = PaymentLinkIntakeState(pendingLink: state.pendingLink);
  }
}

final paymentLinkIntakeProvider =
    NotifierProvider<PaymentLinkIntakeNotifier, PaymentLinkIntakeState>(
      PaymentLinkIntakeNotifier.new,
    );
