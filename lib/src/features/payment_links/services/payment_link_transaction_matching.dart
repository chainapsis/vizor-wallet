import '../../../rust/api/sync.dart' as rust_sync;

/// Rust's broadcast result formats a transaction ID for display, while the
/// transaction-history API currently exposes the same SQLite txid bytes in
/// storage order. Accept both byte orders at this boundary.
bool paymentLinkTxidsMatch(String first, String second) {
  final normalizedFirst = normalizePaymentLinkTxid(first);
  final normalizedSecond = normalizePaymentLinkTxid(second);
  if (normalizedFirst == normalizedSecond) return true;
  if (!_isTransactionIdHex(normalizedFirst) ||
      !_isTransactionIdHex(normalizedSecond)) {
    return false;
  }
  return _reverseHexBytes(normalizedFirst) == normalizedSecond;
}

/// Converts broadcast display-order IDs to the protocol order used by claim
/// records and TransactionInfo. Call only at the broadcast-result boundary;
/// recovered IDs from wallet history already have protocol byte order.
String paymentLinkBroadcastTxidsToProtocolOrder(String txids) {
  return txids
      .split(',')
      .map((txid) {
        final normalized = normalizePaymentLinkTxid(txid);
        if (!_isTransactionIdHex(normalized)) {
          throw const FormatException('Invalid broadcast transaction ID.');
        }
        return _reverseHexBytes(normalized);
      })
      .join(',');
}

bool paymentLinkFundingTransactionExists({
  required String fundingTxid,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  return transactions.any(
    (transaction) =>
        !transaction.expiredUnmined &&
        paymentLinkTxidsMatch(fundingTxid, transaction.txidHex),
  );
}

/// True when every transaction in a comma-separated funding proposal is in
/// [transactions] and not expired.
bool paymentLinkFundingTransactionsExist({
  required String fundingTxids,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  final expectedTxids = fundingTxids
      .split(',')
      .map(normalizePaymentLinkTxid)
      .where((txid) => txid.isNotEmpty)
      .toList();
  if (expectedTxids.isEmpty) return false;
  return expectedTxids.every(
    (txid) => paymentLinkFundingTransactionExists(
      fundingTxid: txid,
      transactions: transactions,
    ),
  );
}

/// Returns true only when every transaction in a funding proposal is known to
/// have expired without being mined.
bool paymentLinkFundingExpired({
  required String fundingTxids,
  required List<rust_sync.TransactionInfo> transactions,
}) {
  final expectedTxids = fundingTxids
      .split(',')
      .map(normalizePaymentLinkTxid)
      .where((txid) => txid.isNotEmpty)
      .toSet();
  if (expectedTxids.isEmpty) return false;

  for (final expectedTxid in expectedTxids) {
    final matching = transactions
        .where(
          (transaction) =>
              paymentLinkTxidsMatch(expectedTxid, transaction.txidHex),
        )
        .toList();
    if (matching.isEmpty ||
        matching.any((transaction) => !transaction.expiredUnmined)) {
      return false;
    }
  }
  return true;
}

String normalizePaymentLinkTxid(String txid) {
  final normalized = txid.trim().toLowerCase();
  return normalized.startsWith('0x') ? normalized.substring(2) : normalized;
}

bool _isTransactionIdHex(String value) {
  return value.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(value);
}

String _reverseHexBytes(String value) {
  final reversed = StringBuffer();
  for (var index = value.length; index > 0; index -= 2) {
    reversed.write(value.substring(index - 2, index));
  }
  return reversed.toString();
}
