import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/sync.dart' as rust_sync;
import '../payment_links/services/payment_link_received_store.dart';
import '../payment_links/services/payment_link_recovery_store.dart';
import '../payment_links/services/payment_link_service.dart';

enum GiftCardActivityKind { created, redeemed }

/// Matches persisted Gift Card lifecycle records to the account's normal
/// on-chain transaction history without changing the transaction-detail model.
class GiftCardActivityIndex {
  const GiftCardActivityIndex({
    this.createdTxids = const <String>{},
    this.redeemedTxids = const <String>{},
  });

  factory GiftCardActivityIndex.forAccount({
    required String accountUuid,
    required List<PaymentLinkRecoveryRecord> createdRecords,
    required List<PaymentLinkReceivedRecord> receivedRecords,
  }) {
    return GiftCardActivityIndex(
      createdTxids: {
        for (final record in createdRecords)
          if (record.sourceAccountUuid == accountUuid)
            ..._splitTxids(record.fundingTxids),
      },
      redeemedTxids: {
        for (final record in receivedRecords)
          if (record.destinationAccountUuid == accountUuid)
            ..._splitTxids(record.claimTxids),
      },
    );
  }

  static const empty = GiftCardActivityIndex();

  final Set<String> createdTxids;
  final Set<String> redeemedTxids;

  GiftCardActivityKind? kindFor(rust_sync.TransactionInfo transaction) {
    final kind = transaction.txKind;
    if ((kind == 'received' || kind == 'receiving') &&
        _matchesAny(redeemedTxids, transaction.txidHex)) {
      return GiftCardActivityKind.redeemed;
    }
    if (kind == 'sent' && _matchesAny(createdTxids, transaction.txidHex)) {
      return GiftCardActivityKind.created;
    }
    return null;
  }
}

final giftCardActivityIndexProvider = FutureProvider.autoDispose
    .family<GiftCardActivityIndex, String>((ref, accountUuid) async {
      final operations = ref.watch(paymentLinkOperationsProvider);
      final records = await Future.wait<Object>([
        operations.loadCreatedLinkRecoveries(),
        operations.loadReceivedLinkRecoveries(),
      ]);
      return GiftCardActivityIndex.forAccount(
        accountUuid: accountUuid,
        createdRecords: records[0] as List<PaymentLinkRecoveryRecord>,
        receivedRecords: records[1] as List<PaymentLinkReceivedRecord>,
      );
    });

Iterable<String> _splitTxids(String? value) sync* {
  if (value == null) return;
  for (final txid in value.split(',')) {
    final trimmed = txid.trim();
    if (trimmed.isNotEmpty) yield trimmed;
  }
}

bool _matchesAny(Set<String> expectedTxids, String transactionTxid) {
  return expectedTxids.any(
    (expectedTxid) => paymentLinkTxidsMatch(expectedTxid, transactionTxid),
  );
}
