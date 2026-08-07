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
  )..removeWhere((record) => record.isArchived);
  final received = List<PaymentLinkReceivedRecord>.of(
    results[1] as List<PaymentLinkReceivedRecord>,
  );
  created.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  received.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return PaymentLinkCardsSnapshot(created: created, received: received);
}
