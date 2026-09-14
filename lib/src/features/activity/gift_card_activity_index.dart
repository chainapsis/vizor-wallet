import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/sync.dart' as rust_sync;
import '../payment_links/services/payment_link_received_store.dart';
import '../payment_links/models/vizor_payment_link.dart';
import '../payment_links/services/payment_link_recovery_store.dart';
import '../payment_links/services/payment_link_lifecycle_revision.dart';
import '../payment_links/services/payment_link_service.dart';
import '../payment_links/services/payment_link_transaction_matching.dart'
    as payment_link_matching;

enum GiftCardActivityKind { created, redeemed }

class GiftCardActivityMetadata {
  const GiftCardActivityMetadata({
    required this.kind,
    required this.amountZatoshi,
    required this.artworkId,
    required this.message,
    this.isClaimInFlight = false,
    this.stableId,
    this.activityTimestamp,
    this.displayPool,
    this.fiatSnapshot,
    this.claimFeeReserveZatoshi,
  }) : assert(
         kind != GiftCardActivityKind.created || claimFeeReserveZatoshi != null,
       );

  final GiftCardActivityKind kind;
  final BigInt amountZatoshi;
  final String? artworkId;
  final String? message;
  final bool isClaimInFlight;
  final String? stableId;
  final DateTime? activityTimestamp;
  final String? displayPool;
  final PaymentLinkFiatSnapshot? fiatSnapshot;
  final BigInt? claimFeeReserveZatoshi;

  BigInt detailFeeZatoshi(BigInt transactionFee) {
    if (kind == GiftCardActivityKind.redeemed) return transactionFee;
    // Gift Card v1 creation uses one funding transaction, so its fee plus the
    // reserved claim fee is the full Card fee; no funding-leg sum is needed.
    // Created Cards always carry that reserve. This unreleased contract has
    // no legacy-record fallback; redeemed Cards use the tx fee.
    return transactionFee + claimFeeReserveZatoshi!;
  }
}

/// Matches persisted Gift Card lifecycle records to the account's normal
/// on-chain transaction history without changing the transaction-detail model.
class GiftCardActivityIndex {
  const GiftCardActivityIndex({
    this.createdTxids = const <String>{},
    this.redeemedTxids = const <String>{},
    this.createdMetadataByTxid = const <String, GiftCardActivityMetadata>{},
    this.redeemedMetadataByTxid = const <String, GiftCardActivityMetadata>{},
    this.pendingClaims = const <PaymentLinkReceivedRecord>[],
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
          amountZatoshi: record.link.amountZatoshi,
          artworkId: record.link.presentation?.artworkId,
          message: record.link.presentation?.message,
          fiatSnapshot: record.link.presentation?.fiatSnapshot,
          claimFeeReserveZatoshi: record.claimFeeReserveZatoshi,
        );
      }
    }
    for (final record in receivedRecords) {
      if (record.destinationAccountUuid != accountUuid) continue;
      for (final txid in _splitTxids(record.claimTxids)) {
        redeemedMetadata[txid] = GiftCardActivityMetadata(
          kind: GiftCardActivityKind.redeemed,
          amountZatoshi: record.amountZatoshi,
          artworkId: record.artworkId,
          message: record.message,
          fiatSnapshot: record.fiatSnapshot,
          isClaimInFlight: record.isClaimInFlight,
          stableId: 'gift-card:${record.address}',
          activityTimestamp: record.claimSubmittedAt,
          displayPool: record.claimDestinationPool,
        );
      }
    }
    return GiftCardActivityIndex(
      createdTxids: createdMetadata.keys.toSet(),
      redeemedTxids: redeemedMetadata.keys.toSet(),
      createdMetadataByTxid: createdMetadata,
      redeemedMetadataByTxid: redeemedMetadata,
      pendingClaims: receivedRecords
          .where(
            (record) =>
                record.destinationAccountUuid == accountUuid &&
                record.status == PaymentLinkReceivedStatus.receiving &&
                _splitTxids(record.claimTxids).isNotEmpty,
          )
          .toList(),
    );
  }

  static const empty = GiftCardActivityIndex();

  final Set<String> createdTxids;
  final Set<String> redeemedTxids;
  final Map<String, GiftCardActivityMetadata> createdMetadataByTxid;
  final Map<String, GiftCardActivityMetadata> redeemedMetadataByTxid;
  final List<PaymentLinkReceivedRecord> pendingClaims;

  /// A submitted claim is visible before the receiver's wallet detects it.
  /// Once a matching receive arrives, its transaction details enrich the same
  /// activity item instead of replacing the business record.
  List<rust_sync.TransactionInfo> withPendingClaims(
    Iterable<rust_sync.TransactionInfo> transactions,
  ) {
    final source = transactions.toList();
    final duplicateInboundIndexes = <int>{};
    for (final record in pendingClaims) {
      final txids = _splitTxids(record.claimTxids).toSet();
      final hasInbound = source.any(
        (tx) =>
            (tx.txKind == 'received' || tx.txKind == 'receiving') &&
            _matchesAny(txids, tx.txidHex),
      );
      if (hasInbound) continue;
      source.add(
        rust_sync.TransactionInfo(
          txidHex: txids.first,
          minedHeight: BigInt.zero,
          expiredUnmined: false,
          accountBalanceDelta: record.amountZatoshi.toInt(),
          fee: BigInt.zero,
          blockTime: BigInt.zero,
          isTransparent: false,
          txKind: 'receiving',
          displayAmount: record.amountZatoshi,
          // Keep the locally observed output pool stable while the receiver's
          // history catches up. A missing value may be enriched later.
          displayPool: record.claimDestinationPool ?? 'unknown',
          createdTime: BigInt.from(
            record.claimSubmittedAt!.millisecondsSinceEpoch ~/ 1000,
          ),
        ),
      );
    }
    // The persisted record remains the business identity after confirmation.
    // A claim that was broadcast in multiple legs must therefore still
    // produce one row once it reaches `received` and leaves pendingClaims.
    final representativeIndexes = <String, int>{};
    for (var index = 0; index < source.length; index++) {
      final transaction = source[index];
      if (transaction.txKind != 'received' &&
          transaction.txKind != 'receiving') {
        continue;
      }
      final stableId = metadataFor(transaction)?.stableId;
      if (stableId == null) continue;
      final previousIndex = representativeIndexes[stableId];
      if (previousIndex == null) {
        representativeIndexes[stableId] = index;
      } else if (source[previousIndex].expiredUnmined &&
          !transaction.expiredUnmined) {
        // An expired leg does not represent a claim with another live leg.
        duplicateInboundIndexes.add(previousIndex);
        representativeIndexes[stableId] = index;
      } else {
        duplicateInboundIndexes.add(index);
      }
    }
    return [
      for (var index = 0; index < source.length; index++)
        if (!duplicateInboundIndexes.contains(index)) source[index],
    ];
  }

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
      if (payment_link_matching.paymentLinkTxidsMatch(
        entry.key,
        transaction.txidHex,
      )) {
        return entry.value;
      }
    }
    return GiftCardActivityMetadata(
      kind: kind,
      amountZatoshi: transaction.displayAmount.abs(),
      artworkId: null,
      message: null,
    );
  }
}

final giftCardActivityIndexProvider = FutureProvider.autoDispose
    .family<GiftCardActivityIndex, String>((ref, accountUuid) async {
      ref.watch(paymentLinkLifecycleRevisionProvider);
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
    (expectedTxid) => payment_link_matching.paymentLinkTxidsMatch(
      expectedTxid,
      transactionTxid,
    ),
  );
}
