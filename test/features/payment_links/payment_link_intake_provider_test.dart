import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';

void main() {
  test('accepts and exposes a valid Vizor payment link', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final link = _link();

    final result = container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(link.toUri().toString());

    expect(result, PaymentLinkIntakeResult.accepted);
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink?.address,
      link.address,
    );
    expect(container.read(paymentLinkIntakeProvider).errorMessage, isNull);
  });

  test(
    'ignores unrelated links so ZIP-321 and HTTPS can share the channel',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = container
          .read(paymentLinkIntakeProvider.notifier)
          .receive('zcash:u1recipient?amount=1');

      expect(result, PaymentLinkIntakeResult.ignored);
      expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);

      expect(
        container
            .read(paymentLinkIntakeProvider.notifier)
            .receive('https://functions.vizor.cash/health'),
        PaymentLinkIntakeResult.ignored,
      );
    },
  );

  test('rejects malformed Vizor links without clearing an earlier secret', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final link = _link();
    final notifier = container.read(paymentLinkIntakeProvider.notifier);
    notifier.receive(link.toUri().toString());

    final result = notifier.receive(
      'https://functions.vizor.cash/payment-links/open#v1=not-base64',
    );

    expect(result, PaymentLinkIntakeResult.rejected);
    final state = container.read(paymentLinkIntakeProvider);
    expect(state.pendingLink?.address, link.address);
    expect(state.errorMessage, isNotNull);
    expect(state.errorMessage, isNot(contains('not-base64')));
  });

  test('takePending removes the link from memory', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(paymentLinkIntakeProvider.notifier);
    final link = _link();
    notifier.receive(link.toUri().toString());

    final taken = notifier.takePending();

    expect(taken?.address, link.address);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
  });

  test('queues multiple accepted links in arrival order', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(paymentLinkIntakeProvider.notifier);
    final first = _link();
    final second = VizorPaymentLink(
      network: first.network,
      address: 'u1secondpaymentlinkaddress',
      amountZatoshi: BigInt.from(200000),
      mnemonic: first.mnemonic,
      birthdayHeight: first.birthdayHeight,
      label: first.label,
      createdAt: first.createdAt.add(const Duration(minutes: 1)),
    );

    notifier.receive(first.toUri().toString());
    notifier.receive(second.toUri().toString());

    expect(notifier.takePending()?.address, first.address);
    expect(notifier.takePending()?.address, second.address);
    expect(notifier.takePending(), isNull);
  });

  test('coalesces duplicate links without growing the queue', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(paymentLinkIntakeProvider.notifier);
    final link = _link();

    expect(
      notifier.receive(link.toUri().toString()),
      PaymentLinkIntakeResult.accepted,
    );
    expect(
      notifier.receive(link.toUri().toString()),
      PaymentLinkIntakeResult.accepted,
    );

    expect(
      container.read(paymentLinkIntakeProvider).pendingLinks,
      hasLength(1),
    );
  });

  test('keeps a corrected claim birthday in the intake queue', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(paymentLinkIntakeProvider.notifier);
    final original = _link();
    final corrected = _link(birthdayHeight: original.birthdayHeight - 1);

    notifier.receive(original.toUri().toString());
    notifier.receive(corrected.toUri().toString());

    expect(
      container
          .read(paymentLinkIntakeProvider)
          .pendingLinks
          .map((link) => link.birthdayHeight),
      [original.birthdayHeight, corrected.birthdayHeight],
    );
  });

  test('rejects unique links beyond the bounded intake queue', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(paymentLinkIntakeProvider.notifier);

    for (var i = 0; i < kPaymentLinkIntakeQueueCapacity; i++) {
      expect(
        notifier.receive(
          _link(address: 'u1paymentlinkaddress$i').toUri().toString(),
        ),
        PaymentLinkIntakeResult.accepted,
      );
    }

    expect(
      notifier.receive(
        _link(address: 'u1paymentlinkoverflow').toUri().toString(),
      ),
      PaymentLinkIntakeResult.rejected,
    );
    final state = container.read(paymentLinkIntakeProvider);
    expect(state.pendingLinks, hasLength(kPaymentLinkIntakeQueueCapacity));
    expect(state.errorMessage, 'Too many payment links are waiting to open.');
  });
}

VizorPaymentLink _link({
  String address = 'u1paymentlinkaddress',
  int birthdayHeight = 3_456_789,
}) {
  return VizorPaymentLink(
    network: 'main',
    address: address,
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: birthdayHeight,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 5, 12),
  );
}
