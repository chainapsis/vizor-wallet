import '../../../rust/api/sync.dart' show BroadcastNotice;

class SwapDepositBroadcastStatus {
  const SwapDepositBroadcastStatus._();

  static const broadcasted = 'broadcasted';
  static const pendingBroadcast = 'pending_broadcast';
  static const partialBroadcast = 'partial_broadcast';
  static const broadcastUnknown = 'broadcast_unknown';
  static const broadcastedStorageFailed = 'broadcasted_storage_failed';
}

class SwapDepositBroadcastResult {
  const SwapDepositBroadcastResult({
    required this.txHash,
    required this.status,
    this.message,
    this.notices = const [],
  });

  final String txHash;
  final String status;

  /// Rust's English result text.
  final String? message;

  /// [message] as sentences for the display language, when Rust wrote it
  /// from them.
  final List<BroadcastNotice> notices;

  bool get isCertain => status == SwapDepositBroadcastStatus.broadcasted;
}
