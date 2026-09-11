import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/pay/providers/cross_chain_payment_request_provider.dart';
import '../../features/send/models/send_prefill_args.dart';
import '../../providers/payment_uri_prefill_provider.dart';
import '../payments/cross_chain_payment_request.dart';
import '../widgets/app_toast.dart';
import '../zcash/zip321_payment_request.dart';
import 'payment_request_draft.dart';
import 'payment_uri_drain_policy.dart';

bool isPaymentRequestUri(String raw) =>
    raw.trim().toLowerCase().startsWith('zcash:') ||
    isCrossChainPaymentUri(raw.trim());

/// One arrival order across native links, QR scans and pasted requests.
/// A slow parser cannot replace a newer request or re-park after a reset.
/// Input surfaces may also invalidate their own submission before it is parked.
class PaymentRequestIntake {
  PaymentRequestIntake(this.ref);
  final Ref ref;
  var _generation = 0;

  void invalidate() => _generation++;

  Future<bool> receive(String raw, {bool Function()? isCurrent}) async {
    final generation = ++_generation;
    final uri = raw.trim();
    try {
      final PaymentRequestDraft draft;
      if (isCrossChainPaymentUri(uri)) {
        draft = await ref.read(crossChainPaymentParserProvider)(uri);
      } else {
        final request = Zip321PaymentRequest.parse(uri);
        if (!request.isSupported) {
          throw Zip321UnsupportedRequestException(request.unsupportedReason!);
        }
        draft = sendPrefillArgsFromZip321Payment(
          id: 'payment-uri-$generation',
          payment: request.primaryPayment,
        );
      }
      if (generation != _generation || isCurrent?.call() == false) {
        return false;
      }
      final replaced = ref.read(paymentUriPrefillProvider.notifier).set(draft);
      ref.read(paymentRequestArrivalProvider.notifier).arrived();
      return replaced;
    } catch (_) {
      if (generation != _generation || isCurrent?.call() == false) {
        return false;
      }
      rethrow;
    }
  }
}

final paymentRequestIntakeProvider = Provider<PaymentRequestIntake>((ref) {
  final intake = PaymentRequestIntake(ref);
  ref.onDispose(intake.invalidate);
  return intake;
});

/// Returns false for a plain address or a cancelled input surface. Parsing
/// failures remain explicit so the
/// input surface can show them without silently treating a request as an address.
Future<bool> intakePaymentRequest(
  WidgetRef ref,
  String raw, {
  bool Function()? isCurrent,
}) async {
  if (!isPaymentRequestUri(raw)) return false;
  final replaced = await ref
      .read(paymentRequestIntakeProvider)
      .receive(raw, isCurrent: isCurrent);
  if (isCurrent?.call() == false) return false;
  if (replaced && ref.context.mounted) {
    showAppToast(ref.context, kPaymentUriReplacedMessage);
  }
  return true;
}

class PaymentRequestArrivalNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void arrived() => state++;
}

final paymentRequestArrivalProvider =
    NotifierProvider<PaymentRequestArrivalNotifier, int>(
      PaymentRequestArrivalNotifier.new,
    );
