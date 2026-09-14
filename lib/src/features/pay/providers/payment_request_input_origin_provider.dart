import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';

/// A live address editor that can consume just the recipient of a request.
/// This is local UI state: it is never serialized or restored after locking.
class PaymentRequestInputOrigin {
  const PaymentRequestInputOrigin({
    required this.chain,
    required this.isCurrent,
    required this.useAddress,
    this.onCancel,
  });

  final String chain;
  final bool Function() isCurrent;
  final void Function(String address) useAddress;
  final void Function()? onCancel;
}

class PendingPaymentRequestInputOrigin {
  const PendingPaymentRequestInputOrigin(this.requestId, this.origin);
  final String requestId;
  final PaymentRequestInputOrigin origin;
}

class PaymentRequestInputOriginNotifier
    extends Notifier<PendingPaymentRequestInputOrigin?> {
  @override
  PendingPaymentRequestInputOrigin? build() {
    ref.listen(appSecurityProvider.select((value) => value.isUnlocked), (
      _,
      unlocked,
    ) {
      if (!unlocked) state = null;
    });
    ref.listen(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (_, _) {
        state = null;
      },
    );
    return null;
  }

  void set(String requestId, PaymentRequestInputOrigin? origin) {
    state = origin == null
        ? null
        : PendingPaymentRequestInputOrigin(requestId, origin);
  }

  PaymentRequestInputOrigin? take(String requestId) {
    final pending = state;
    state = null;
    return pending?.requestId == requestId ? pending!.origin : null;
  }
}

final paymentRequestInputOriginProvider =
    NotifierProvider<
      PaymentRequestInputOriginNotifier,
      PendingPaymentRequestInputOrigin?
    >(PaymentRequestInputOriginNotifier.new);
