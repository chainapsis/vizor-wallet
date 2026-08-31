import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/sync.dart' as rust_sync;
import '../payment_links/services/payment_link_received_store.dart';
import '../payment_links/services/payment_link_recovery_store.dart';
import '../payment_links/services/payment_link_service.dart';

enum GiftCardActivityKind { created, redeemed }

class GiftCardActivityMetadata {
  const GiftCardActivityMetadata({
    required this.kind,
    required this.artworkId,
    required this.message,
  });

  final GiftCardActivityKind kind;
  final String? artworkId;
  final String? message;
}

/// Matches persisted Gift Card lifecycle records to the account's normal
/// on-chain transaction history without changing the transaction-detail model.
class GiftCardActivityIndex {
  const GiftCardActivityIndex({
    this.createdTxids = const <String>{},
    this.redeemedTxids = const <String>{},
    this.createdMetadataByTxid = const <String, GiftCardActivityMetadata>{},
    this.redeemedMetadataByTxid = const <String, GiftCardActivityMetadata>{},
  });

  factory GiftCardActivityIndex.forAccount({
    required String accountUuid,
    required List<PaymentLinkRecoveryRecord> createdRecords,
    required List<PaymentLinkReceivedRecord> receivedRecords,
  }) {
    final createdMetadata = <String, GiftCardActivityMetadata>{};
    final redeemedMetadata = <String, GiftCardActivityMetadata>{};
    for (final record in createdRecords) {
      if (record.sourceAccountUuid != accountUuid) continue;
      for (final txid in _splitTxids(record.fundingTxids)) {
        createdMetadata[txid] = GiftCardActivityMetadata(
          kind: GiftCardActivityKind.created,
          artworkId: record.link.presentation?.artworkId,
          message: record.link.presentation?.message,
        );
      }
    }
    for (final record in receivedRecords) {
      if (record.destinationAccountUuid != accountUuid) continue;
      for (final txid in _splitTxids(record.claimTxids)) {
        redeemedMetadata[txid] = GiftCardActivityMetadata(
          kind: GiftCardActivityKind.redeemed,
          artworkId: record.artworkId,
          message: record.message,
        );
      }
    }
    return GiftCardActivityIndex(
      createdTxids: createdMetadata.keys.toSet(),
      redeemedTxids: redeemedMetadata.keys.toSet(),
      createdMetadataByTxid: createdMetadata,
      redeemedMetadataByTxid: redeemedMetadata,
    );
  }

  static const empty = GiftCardActivityIndex();

  final Set<String> createdTxids;
  final Set<String> redeemedTxids;
  final Map<String, GiftCardActivityMetadata> createdMetadataByTxid;
  final Map<String, GiftCardActivityMetadata> redeemedMetadataByTxid;

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

  GiftCardActivityMetadata? metadataFor(rust_sync.TransactionInfo transaction) {
    final kind = kindFor(transaction);
    if (kind == null) return null;
    final metadata = kind == GiftCardActivityKind.created
        ? createdMetadataByTxid
        : redeemedMetadataByTxid;
    for (final entry in metadata.entries) {
      if (paymentLinkTxidsMatch(entry.key, transaction.txidHex)) {
        return entry.value;
      }
    }
    return GiftCardActivityMetadata(kind: kind, artworkId: null, message: null);
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
