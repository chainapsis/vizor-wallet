import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/payment_link_received_store.dart';
import '../services/payment_link_recovery_store.dart';
import '../services/payment_link_service.dart';

@immutable
class PaymentLinkCardsSnapshot {
  const PaymentLinkCardsSnapshot({
    required this.created,
    required this.received,
  });

  final List<PaymentLinkRecoveryRecord> created;
  final List<PaymentLinkReceivedRecord> received;
}

typedef PaymentLinkCardsLoader = Future<PaymentLinkCardsSnapshot> Function();

/// Sharing or refreshing a card must not move it in the created-card list.
int compareCreatedPaymentLinks(
  PaymentLinkRecoveryRecord a,
  PaymentLinkRecoveryRecord b,
) {
  final byCreation = b.link.createdAt.compareTo(a.link.createdAt);
  return byCreation != 0
      ? byCreation
      : a.link.address.compareTo(b.link.address);
}

final paymentLinkCardsLoaderProvider = Provider<PaymentLinkCardsLoader>((ref) {
  final operations = ref.watch(paymentLinkOperationsProvider);
  return () => loadPaymentLinkCardsSnapshot(operations);
});

Future<PaymentLinkCardsSnapshot> loadPaymentLinkCardsSnapshot(
  PaymentLinkOperations operations,
) async {
  final results = await Future.wait<Object>([
    operations.loadCreatedLinkRecoveries(),
    operations.loadReceivedLinkRecoveries(),
  ]);
  final created = List<PaymentLinkRecoveryRecord>.of(
    results[0] as List<PaymentLinkRecoveryRecord>,
  );
  final received = List<PaymentLinkReceivedRecord>.of(
    results[1] as List<PaymentLinkReceivedRecord>,
  );
  created.sort(compareCreatedPaymentLinks);
  received.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return PaymentLinkCardsSnapshot(created: created, received: received);
}
