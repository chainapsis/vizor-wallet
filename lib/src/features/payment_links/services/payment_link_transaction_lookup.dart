import '../../../rust/api/sync.dart' as rust_sync;
import 'payment_link_transaction_matching.dart';

typedef PaymentLinkTransactionRowsLoader =
    Future<List<rust_sync.TransactionInfo>> Function(
      String accountUuid,
      List<String> txids,
    );

void addPaymentLinkTransactionIds(
  Map<String, Set<String>> byAccount,
  String accountUuid,
  String? rawTxids,
) {
  final txids = {
    for (final raw in rawTxids?.split(',') ?? const <String>[])
      if (normalizePaymentLinkTxid(raw).isNotEmpty)
        normalizePaymentLinkTxid(raw),
  }.toList()..sort();
  if (txids.isNotEmpty) (byAccount[accountUuid] ??= {}).add(txids.join(','));
}

/// Values are comma-separated TXID groups, one funding/claim proposal each.
/// Only requested rows cross the bridge. Batches normally contain at most 128
/// IDs; a single larger proposal stays intact to preserve its DB snapshot.
Future<Map<String, List<rust_sync.TransactionInfo>>>
loadPaymentLinkTransactionRows({
  required String dbPath,
  required String network,
  required Map<String, Set<String>> txidsByAccount,
  PaymentLinkTransactionRowsLoader? loadRows,
}) async {
  final loader =
      loadRows ??
      (account, txids) => rust_sync.getTransactionRowsForTxids(
        dbPath: dbPath,
        network: network,
        accountUuid: account,
        txidHexes: txids,
      );
  final result = <String, List<rust_sync.TransactionInfo>>{};
  for (final entry in txidsByAccount.entries) {
    final rows = <rust_sync.TransactionInfo>[];
    for (final batch in _transactionBatches(entry.value)) {
      rows.addAll(await loader(entry.key, batch));
    }
    result[entry.key] = rows;
  }
  return result;
}

/// Normalizes and indexes each transaction once per refresh. Each card then
/// visits just its own rows, including all activity rows of a split transaction.
class PaymentLinkTransactionIndex {
  PaymentLinkTransactionIndex(Iterable<rust_sync.TransactionInfo> rows) {
    for (final row in rows) {
      (_byTxid[paymentLinkTransactionKey(row.txidHex)] ??= []).add(row);
    }
  }

  final _byTxid = <String, List<rust_sync.TransactionInfo>>{};

  List<rust_sync.TransactionInfo> matching(String? rawTxids) {
    final keys = {
      for (final txid in rawTxids?.split(',') ?? const <String>[])
        paymentLinkTransactionKey(txid),
    };
    return [for (final key in keys) ...?_byTxid[key]];
  }
}

class _TransactionGroup {
  final keys = <String>{};
  final txids = <String>{};
}

/// Keep overlapping proposals together too: indexing rows from two snapshots
/// must not replace one leg of a proposal with a newer read of a shared leg.
List<List<String>> _transactionBatches(Set<String> proposals) {
  final groupByKey = <String, _TransactionGroup>{};
  for (final proposal in proposals) {
    var group = _TransactionGroup();
    for (final raw in proposal.split(',')) {
      final txid = normalizePaymentLinkTxid(raw);
      if (txid.isEmpty) continue;
      final key = paymentLinkTransactionKey(txid);
      var existing = groupByKey[key];
      if (existing != null && !identical(existing, group)) {
        // Union by size keeps repeated overlapping proposals linearithmic.
        if (group.keys.length < existing.keys.length) {
          final small = group;
          group = existing;
          existing = small;
        }
        for (final oldKey in existing.keys) {
          groupByKey[oldKey] = group;
        }
        group.keys.addAll(existing.keys);
        group.txids.addAll(existing.txids);
      }
      group.keys.add(key);
      groupByKey[key] = group;
      group.txids.add(txid);
      final reversed = paymentLinkTxidInOtherByteOrder(txid);
      if (reversed != null) group.txids.add(reversed);
    }
  }
  final batches = <List<String>>[];
  var batch = <String>[];
  for (final group in groupByKey.values.toSet()) {
    if (batch.isNotEmpty && batch.length + group.txids.length > 128) {
      batches.add(batch);
      batch = <String>[];
    }
    batch.addAll(group.txids);
  }
  if (batch.isNotEmpty) batches.add(batch);
  return batches;
}
