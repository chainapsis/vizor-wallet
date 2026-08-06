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
        .ingest(link.encode());

    expect(result, PaymentLinkIntakeResult.accepted);
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink?.address,
      link.address,
    );
    expect(container.read(paymentLinkIntakeProvider).errorMessage, isNull);
  });

  test('ignores other URI schemes so ZIP-321 can share the channel', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = container
        .read(paymentLinkIntakeProvider.notifier)
        .ingest('zcash:u1recipient?amount=1');

    expect(result, PaymentLinkIntakeResult.ignored);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
  });

  test('rejects malformed Vizor links without clearing an earlier secret', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final link = _link();
    final notifier = container.read(paymentLinkIntakeProvider.notifier);
    notifier.ingest(link.encode());

    final result = notifier.ingest('vizor://payment-link?p=not-base64');

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
    notifier.ingest(link.encode());

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

    notifier.ingest(first.encode());
    notifier.ingest(second.encode());

    expect(notifier.takePending()?.address, first.address);
    expect(notifier.takePending()?.address, second.address);
    expect(notifier.takePending(), isNull);
  });
}

VizorPaymentLink _link() {
  return VizorPaymentLink(
    network: 'main',
    address: 'u1paymentlinkaddress',
    amountZatoshi: BigInt.from(100000),
    mnemonic:
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    birthdayHeight: 3_456_789,
    label: 'Payment link',
    createdAt: DateTime.utc(2026, 8, 5, 12),
  );
}
