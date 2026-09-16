import 'package:flutter/foundation.dart';

/// Debug-only metadata. Never pass account IDs, keys, addresses, PCZT/APDU
/// payloads, signatures, or exception messages to this logger.
void ledgerTrace(String metadata) {
  if (kDebugMode) {
    debugPrint(
      '[LedgerTrace][dart] utc=${DateTime.now().toUtc().toIso8601String()} $metadata',
    );
  }
}
