import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentLinkLifecycleRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

final paymentLinkLifecycleRevisionProvider =
    NotifierProvider<PaymentLinkLifecycleRevisionNotifier, int>(
      PaymentLinkLifecycleRevisionNotifier.new,
    );
