/// Builds a stable hide-key string that identifies one received memo output.
///
/// Two sources must produce the same key for the same output:
/// - The inbox list (`ReceivedMemo` from Rust) exposes `txidHex`,
///   `outputPool` (int), and `outputIndex` (int) — use [memoHideKey].
/// - The transaction detail screen (`TransactionDetail.memoOutputKey` from
///   Rust) is already the "pool:index" substring — use [memoHideKeyFromDetail].
///
/// Both helpers produce the identical canonical form `"txid:pool:index"`.
library;

/// Builds a memo hide-key from the three discrete fields exposed by
/// `ReceivedMemo`. Produces the canonical form `"txidHex:outputPool:outputIndex"`.
///
/// This aligns with [memoHideKeyFromDetail] so that keys derived from the
/// inbox list and from the detail screen always match.
String memoHideKey({
  required String txidHex,
  required int outputPool,
  required int outputIndex,
}) =>
    '$txidHex:$outputPool:$outputIndex';

/// Builds a memo hide-key from the pre-formatted `memoOutputKey` string
/// (`"pool:index"`) that `TransactionDetail` exposes, combined with `txidHex`.
/// Produces the canonical form `"txidHex:pool:index"`.
///
/// This aligns with [memoHideKey] so that keys derived from the inbox list and
/// from the detail screen always match.
String memoHideKeyFromDetail({
  required String txidHex,
  required String memoOutputKey, // "pool:index"
}) =>
    '$txidHex:$memoOutputKey';
