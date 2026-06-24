import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

enum SendFailureKind {
  syncInProgress,
  scanRequired,
  insufficientFunds,
  unknown,
}

extension SendFailureKindChecks on SendFailureKind {
  bool get isWaitingForSync =>
      this == SendFailureKind.syncInProgress ||
      this == SendFailureKind.scanRequired;
}

SendFailureKind classifySendFailure(Object error) {
  final raw = error is AnyhowException ? error.message : error.toString();
  const markers = {
    'sync_in_progress|': SendFailureKind.syncInProgress,
    'scan_required|': SendFailureKind.scanRequired,
    'insufficient_funds|': SendFailureKind.insufficientFunds,
  };

  for (final entry in markers.entries) {
    if (raw.contains(entry.key)) return entry.value;
  }

  return SendFailureKind.unknown;
}
