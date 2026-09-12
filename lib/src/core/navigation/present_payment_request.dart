import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../payments/cross_chain_payment_request.dart';
import '../../features/pay/providers/cross_chain_payment_request_provider.dart';
import '../../features/send/models/send_prefill_args.dart';
import '../../providers/payment_request_flow_provider.dart';
import 'payment_request_draft.dart';

/// A single request can own the overlay. Switching execution lanes releases
/// the previous Zcash proposal instead of leaving an invisible reservation.
void presentPaymentRequest(
  WidgetRef ref,
  PaymentRequestDraft request, {
  PaymentRequestSource source = PaymentRequestSource.link,
}) {
  if (request is SendPrefillArgs) {
    ref.read(crossChainPaymentFlowProvider.notifier).clear();
    ref
        .read(paymentRequestFlowProvider.notifier)
        .present(request, source: source);
  } else if (request is CrossChainPaymentRequest) {
    ref.read(paymentRequestFlowProvider.notifier).clear();
    ref.read(crossChainPaymentFlowProvider.notifier).present(request);
  }
}
