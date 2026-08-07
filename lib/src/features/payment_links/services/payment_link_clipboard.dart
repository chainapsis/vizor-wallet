import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';

abstract interface class PaymentLinkClipboard {
  Future<String?> readText();

  Future<void> copySecret(String text);

  Future<void> clear();
}

final paymentLinkClipboardProvider = Provider<PaymentLinkClipboard>((ref) {
  return const SystemPaymentLinkClipboard();
});

class SystemPaymentLinkClipboard implements PaymentLinkClipboard {
  const SystemPaymentLinkClipboard();

  @override
  Future<String?> readText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> copySecret(String text) {
    return SensitiveClipboard.copyText(text);
  }

  @override
  Future<void> clear() {
    return Clipboard.setData(const ClipboardData(text: ''));
  }
}
