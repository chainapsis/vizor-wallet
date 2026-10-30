import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/sync.dart' as rust_sync;
import '../payment_links/services/payment_link_received_store.dart';
import '../payment_links/models/vizor_payment_link.dart';
import '../payment_links/services/payment_link_recovery_store.dart';
import '../payment_links/services/payment_link_lifecycle_revision.dart';
import '../payment_links/services/payment_link_service.dart';
import '../payment_links/services/payment_link_store_codec.dart';
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
    this.batchCount,
    this.amountPerCardZatoshi,
    this.claimTxids = const [],
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
  final int? batchCount;
  final BigInt? amountPerCardZatoshi;
  final List<String> claimTxids;

  GiftCardActivityMetadata withDisplayPool(String pool) =>
      GiftCardActivityMetadata(
        kind: kind,
        amountZatoshi: amountZatoshi,
        artworkId: artworkId,
        message: message,
        isClaimInFlight: isClaimInFlight,
        stableId: stableId,
        activityTimestamp: activityTimestamp,
        displayPool: pool,
        fiatSnapshot: fiatSnapshot,
        claimFeeReserveZatoshi: claimFeeReserveZatoshi,
        batchCount: batchCount,
        amountPerCardZatoshi: amountPerCardZatoshi,
        claimTxids: claimTxids,
      );

  BigInt detailFeeZatoshi(BigInt transactionFee) {
    if (kind == GiftCardActivityKind.redeemed) return transactionFee;
    // Gift Card creation uses one funding transaction, so its fee plus the
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
  }) : _createdByKey = null,
       _redeemedByKey = null;

  GiftCardActivityIndex._indexed(GiftCardActivityIndex source)
    : createdTxids = source.createdTxids,
      redeemedTxids = source.redeemedTxids,
      createdMetadataByTxid = source.createdMetadataByTxid,
      redeemedMetadataByTxid = source.redeemedMetadataByTxid,
      pendingClaims = source.pendingClaims,
      _createdByKey = _indexMetadata(source.createdMetadataByTxid),
      _redeemedByKey = _indexMetadata(source.redeemedMetadataByTxid);

  final Map<String, GiftCardActivityMetadata>? _createdByKey;
  final Map<String, GiftCardActivityMetadata>? _redeemedByKey;

  static Map<String, GiftCardActivityMetadata> _indexMetadata(
    Map<String, GiftCardActivityMetadata> metadata,
  ) {
    final result = <String, GiftCardActivityMetadata>{};
    for (final entry in metadata.entries) {
      result.putIfAbsent(
        payment_link_matching.paymentLinkTransactionKey(entry.key),
        () => entry.value,
      );
    }
    return result;
  }

  factory GiftCardActivityIndex.forAccount({
    required String accountUuid,
    required List<PaymentLinkRecoveryRecord> createdRecords,
    required List<PaymentLinkReceivedRecord> receivedRecords,
  }) {
    final createdMetadata = <String, GiftCardActivityMetadata>{};
    final redeemedMetadata = <String, GiftCardActivityMetadata>{};
    final batchRecordsByTxid = <String, List<PaymentLinkRecoveryRecord>>{};
    for (final record in createdRecords) {
      if (record.sourceAccountUuid != accountUuid) continue;
      for (final txid in _splitTxids(record.fundingTxids)) {
        if (record.batchId != null) {
          (batchRecordsByTxid[txid] ??= []).add(record);
          continue;
        }
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
    for (final entry in batchRecordsByTxid.entries) {
      final first = entry.value.first;
      // The transaction funded every card, even after some records are gone.
      final count = BigInt.from(first.batchCount ?? entry.value.length);
      final amountPerCard = first.link.amountZatoshi;
      createdMetadata[entry.key] = GiftCardActivityMetadata(
        kind: GiftCardActivityKind.created,
        amountZatoshi: amountPerCard * count,
        artworkId: first.link.presentation?.artworkId,
        message: first.link.presentation?.message,
        claimFeeReserveZatoshi: first.claimFeeReserveZatoshi * count,
        batchCount: count.toInt(),
        amountPerCardZatoshi: amountPerCard,
        stableId: 'gift-card-batch:${first.batchId}',
      );
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
          claimTxids: _splitTxids(record.claimTxids).toList(growable: false),
        );
      }
    }
    return GiftCardActivityIndex._indexed(
      GiftCardActivityIndex(
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
      ),
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
    final inboundKeys = {
      for (final tx in source)
        if (tx.txKind == 'received' || tx.txKind == 'receiving')
          payment_link_matching.paymentLinkTransactionKey(tx.txidHex),
    };
    for (final record in pendingClaims) {
      final txids = _splitTxids(record.claimTxids).toSet();
      final hasInbound = txids.any(
        (txid) => inboundKeys.contains(
          payment_link_matching.paymentLinkTransactionKey(txid),
        ),
      );
      if (hasInbound) continue;
      inboundKeys.add(
        payment_link_matching.paymentLinkTransactionKey(txids.first),
      );
      source.add(
        rust_sync.TransactionInfo(
          txidHex: txids.first,
          minedHeight: BigInt.zero,
          expiredUnmined: false,
          accountBalanceDelta: record.amountZatoshi.toInt(),
          fee: BigInt.zero,
          feeState: rust_sync.TransactionFeeState.notApplicable,
          detailsComplete: true,
          provisional: false,
          amountIncludesFee: false,
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
        (_redeemedByKey?.containsKey(
              payment_link_matching.paymentLinkTransactionKey(
                transaction.txidHex,
              ),
            ) ??
            _matchesAny(redeemedTxids, transaction.txidHex))) {
      return GiftCardActivityKind.redeemed;
    }
    if (kind == 'sent' &&
        (_createdByKey?.containsKey(
              payment_link_matching.paymentLinkTransactionKey(
                transaction.txidHex,
              ),
            ) ??
            _matchesAny(createdTxids, transaction.txidHex))) {
      return GiftCardActivityKind.created;
    }
    return null;
  }

  GiftCardActivityMetadata? metadataFor(
    rust_sync.TransactionInfo transaction, {
    Iterable<rust_sync.TransactionInfo>? transactions,
  }) {
    final kind = kindFor(transaction);
    if (kind == null) return null;
    final metadata = kind == GiftCardActivityKind.created
        ? createdMetadataByTxid
        : redeemedMetadataByTxid;
    final indexed = kind == GiftCardActivityKind.created
        ? _createdByKey
        : _redeemedByKey;
    final GiftCardActivityMetadata? card;
    if (indexed != null) {
      card =
          indexed[payment_link_matching.paymentLinkTransactionKey(
            transaction.txidHex,
          )];
    } else {
      card = metadata.entries
          .where(
            (entry) => payment_link_matching.paymentLinkTxidsMatch(
              entry.key,
              transaction.txidHex,
            ),
          )
          .firstOrNull
          ?.value;
    }
    if (card != null) {
      if (kind == GiftCardActivityKind.redeemed &&
          paymentLinkClaimPoolNeedsEnrichment(card.displayPool) &&
          card.claimTxids.isNotEmpty) {
        final pool = paymentLinkClaimDestinationPoolFromHistory(
          claimTxids: card.claimTxids.join(','),
          transactions: transactions ?? [transaction],
        );
        // An incomplete multi-leg claim must not inherit its representative's pool.
        return card.withDisplayPool(pool ?? card.displayPool ?? 'unknown');
      }
      return card;
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
        operations.loadCreatedLinks(),
        operations.loadReceivedLinkRecoveries(),
      ]);
      final created = records[0] as List<PaymentLinkRecoveryRecord>;
      final received = records[1] as List<PaymentLinkReceivedRecord>;
      return runPaymentLinkStoreCodec(
        _buildGiftCardActivityIndex,
        (accountUuid: accountUuid, created: created, received: received),
        inBackground:
            created.length + received.length >=
            paymentLinkCodecBackgroundRecords,
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

GiftCardActivityIndex _buildGiftCardActivityIndex(
  ({
    String accountUuid,
    List<PaymentLinkRecoveryRecord> created,
    List<PaymentLinkReceivedRecord> received,
  })
  input,
) => GiftCardActivityIndex.forAccount(
  accountUuid: input.accountUuid,
  createdRecords: input.created,
  receivedRecords: input.received,
);
