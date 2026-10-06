import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/wallet_paths.dart';
import '../../providers/account_provider.dart';
import '../../providers/pending_activity_evidence_provider.dart';
import '../../providers/rpc_endpoint_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/sync_failure.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../swap/providers/swap_activity_store.dart';
import 'gift_card_activity_index.dart';
import '../swap/models/swap_chain_txid.dart';

/// Stale observations and local recovery do not imply a lost connection.
final activityPendingFallbackLabelProvider = Provider<String>((ref) {
  final connectionFailed = ref.watch(
    pendingActivityEvidenceProvider.select((s) => s.connectionFailed),
  );
  final failure = ref.watch(syncProvider.select((s) => s.value?.failure?.kind));
  return connectionFailed ||
          failure == SyncFailureKind.network ||
          failure == SyncFailureKind.torUnavailable
      ? 'Waiting for connection'
      : 'Checking status';
});

/// Identity of the successful sync snapshot against which history was read.
/// A completed sync can recover transaction status even at unchanged heights;
/// a simple history refresh within that snapshot may retain the prior estimate.
(int?, int?, DateTime?) activityHistorySnapshot(SyncState? sync) =>
    (sync?.scannedHeight, sync?.chainTipHeight, sync?.lastSyncCompletedAt);

/// Stable values avoid reloads when resume merely recreates the same list.
String activityHistoryStatusSignature(
  Iterable<rust_sync.TransactionInfo> transactions,
) => transactions
    .map(
      (tx) =>
          '${tx.txidHex}:${tx.minedHeight}:${tx.expiredUnmined}:${tx.txKind}:'
          '${tx.displayAmount}:${tx.fundingParentTxid}:'
          '${tx.fundingParentMinedHeight}:${tx.fundingParentExpired}',
    )
    .join('|');

typedef ActivityEtaClaimHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(
      String accountUuid,
      String network,
    );

final activityEtaClaimHistoryLoaderProvider =
    Provider<ActivityEtaClaimHistoryLoader>(
      (ref) =>
          (accountUuid, network) async => rust_sync.getTransactionHistory(
            dbPath: await getWalletDbPath(),
            network: network,
            accountUuid: accountUuid,
          ),
    );

String _fundingKey(String txid) => 'funding:${activityTxidKey(txid)}';

/// Includes linked legs even when a refunded/expired swap leaves its Sent row
/// visible. Missing classification data withholds numeric estimates below.
final activityEtaExcludedTxidsProvider = Provider<Set<String>>((ref) {
  final account = ref.watch(accountProvider).value?.activeAccountUuid;
  if (account == null) return const {};
  final records = ref.watch(swapActivityRecordsProvider(account)).value;
  return {
    for (final record in records ?? [])
      for (final hash in [
        record.depositTxHash,
        record.originChainTxHash,
        record.destinationChainTxHash,
      ])
        if (swapChainTxidToWalletTxidHex(hash) case final String txid)
          activityTxidKey(txid),
  };
});

/// Only multi-leg pending claims need history beyond Home's recent ten. This
/// is a shared local DB read, refreshed on wallet/history/lifecycle changes;
/// the ETA clock does not trigger additional reads or network requests.
final activityEtaClaimHistoryProvider =
    FutureProvider<List<rust_sync.TransactionInfo>>((ref) async {
      final account = ref.watch(accountProvider).value?.activeAccountUuid;
      if (account == null) return const [];
      final index = ref.watch(giftCardActivityIndexProvider(account)).value;
      final needsHistory =
          index?.pendingClaims.any(
            (r) =>
                (r.claimTxids
                        ?.split(',')
                        .where((id) => id.trim().isNotEmpty)
                        .length ??
                    0) >
                1,
          ) ??
          false;
      if (!needsHistory) return const [];
      final sync = ref.watch(
        syncProvider.select(
          (s) => (
            s.value?.accountUuid,
            s.value?.isSyncing,
            activityHistorySnapshot(s.value),
            activityHistoryStatusSignature(
              s.value?.recentTransactions ?? const [],
            ),
          ),
        ),
      );
      if (sync.$1 != account || sync.$2 != false) return const [];
      final endpoint = ref.watch(rpcEndpointProvider);
      return ref.watch(activityEtaClaimHistoryLoaderProvider)(
        account,
        endpoint.networkName,
      );
    });

/// Shared by all four feeds. Keys use canonical local txids; a funding key
/// carries the conservative TEX range and a Gift Card stable ID its group ETA.
final activityEtaLabelsProvider = Provider<Map<String, String>>((ref) {
  final evidence = ref.watch(pendingActivityEvidenceProvider);
  final sync = ref.watch(syncProvider).value;
  final account = ref.watch(accountProvider).value?.activeAccountUuid;
  if (account == null ||
      sync == null ||
      sync.accountUuid != account ||
      !sync.hasAccountScopedData ||
      !sync.isSyncComplete ||
      sync.isSyncing ||
      sync.failure != null) {
    return const {};
  }
  final gifts = ref.watch(giftCardActivityIndexProvider(account));
  final swaps = ref.watch(swapActivityRecordsProvider(account));
  if (!gifts.hasValue || gifts.hasError || !swaps.hasValue || swaps.hasError) {
    return const {};
  }
  final excluded = ref.watch(activityEtaExcludedTxidsProvider);
  final labels = <String, String>{};
  for (final entry in evidence.observedAt.entries) {
    final id = entry.key.$2;
    if (entry.key.$1 != account || excluded.contains(id)) continue;
    final ordinary = evidence.labelFor(account, id, sync.scannedHeight);
    final funding = evidence.labelFor(
      account,
      id,
      sync.scannedHeight,
      waitingForFunding: true,
    );
    if (ordinary != null) labels[id] = ordinary;
    if (funding != null) labels[_fundingKey(id)] = funding;
  }
  final history = ref.watch(activityEtaClaimHistoryProvider);
  final hasVerifiedClaimHistory =
      history.hasValue && !history.isLoading && !history.hasError;
  final transactions = hasVerifiedClaimHistory
      ? history.value!
      : const <rust_sync.TransactionInfo>[];
  for (final claim in gifts.value!.pendingClaims) {
    final ids = claim.claimTxids!
        .split(',')
        .map(activityTxidKey)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.length <= 1 || !hasVerifiedClaimHistory) continue;
    final label = giftCardClaimEtaLabel(
      ids: ids,
      transactions: transactions,
      scannedHeight: sync.scannedHeight,
      labels: labels,
    );
    if (label != null) labels['gift-card:${claim.address}'] = label;
  }
  return labels;
});

String? activityEtaLabelFor({
  required rust_sync.TransactionInfo transaction,
  required Map<String, String> labels,
  GiftCardActivityMetadata? giftCard,
}) {
  if (giftCard != null && giftCard.claimTxids.length > 1) {
    return labels[giftCard.stableId];
  }
  final id = activityTxidKey(transaction.txidHex);
  if (transaction.fundingParentTxid != null) {
    if (transaction.fundingParentExpired != false ||
        transaction.fundingParentMinedHeight == null) {
      return null;
    }
    if (transaction.fundingParentMinedHeight == BigInt.zero) {
      return labels[_fundingKey(id)];
    }
  }
  return labels[id] ?? labels[transaction.txidHex];
}

/// A pending claim's representative row may already be mined. Estimate the
/// entire business operation from all legs; missing or expired legs withhold it.
String? giftCardClaimEtaLabel({
  required Set<String> ids,
  required Iterable<rust_sync.TransactionInfo> transactions,
  required int scannedHeight,
  required Map<String, String> labels,
}) {
  final remaining = <String>[];
  for (final rawId in ids) {
    final id = activityTxidKey(rawId);
    final tx = transactions
        .where(
          (tx) =>
              activityTxidKey(tx.txidHex) == id &&
              (tx.txKind == 'received' || tx.txKind == 'receiving'),
        )
        .firstOrNull;
    if (tx?.expiredUnmined == true) return null;
    if (tx != null &&
        tx.minedHeight > BigInt.zero &&
        tx.minedHeight <= BigInt.from(scannedHeight)) {
      continue;
    }
    final label = labels[id];
    if (label == null) return null;
    remaining.add(label);
  }
  if (remaining.isEmpty) return null;
  return remaining.contains('Taking longer') ? 'Taking longer' : 'Est. 1–3 min';
}
