import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';

// The prefill parks one `zcash:` link at a time — latest wins, no queue — so
// `set` is the only place that can tell a first arrival from one that
// displaced a link the user has not seen yet. Its return value is what
// `_PaymentUriLinkListener` uses to surface `kPaymentUriReplacedMessage`
// instead of dropping the earlier link in silence.
void main() {
  const first = SendPrefillArgs(
    id: 'payment-uri-1',
    source: 'zcash-uri',
    address: 'u1first',
    amountText: '0.5',
  );
  const second = SendPrefillArgs(
    id: 'payment-uri-2',
    source: 'zcash-uri',
    address: 'u1second',
    amountText: '0.25',
  );

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('set reports a replacement only when a prefill is still parked', () {
    final container = makeContainer();
    final notifier = container.read(paymentUriPrefillProvider.notifier);

    // Nothing parked: the first link replaces nothing.
    expect(notifier.set(first), isFalse);
    expect(container.read(paymentUriPrefillProvider), first);

    // A second link arrives before the first is drained or claimed.
    expect(notifier.set(second), isTrue);
    expect(container.read(paymentUriPrefillProvider), second);

    // Once the parked link is gone, the next one is a first arrival again.
    notifier.clear();
    expect(notifier.set(first), isFalse);
    expect(container.read(paymentUriPrefillProvider), first);
  });

  test(
    'a duplicate delivery of the same link still counts as a replacement',
    () {
      final container = makeContainer();
      final notifier = container.read(paymentUriPrefillProvider.notifier);

      expect(notifier.set(first), isFalse);
      expect(notifier.set(first), isTrue);
    },
  );

  test(
    'take and takeIfFresh clear the park, so the next set is not a replacement',
    () {
      final container = makeContainer();
      final notifier = container.read(paymentUriPrefillProvider.notifier);

      notifier.set(first);
      expect(notifier.take(), first);
      expect(notifier.set(second), isFalse);

      expect(notifier.takeIfFresh(), second);
      expect(notifier.set(first), isFalse);
    },
  );
}
