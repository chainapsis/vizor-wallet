import 'package:flutter/foundation.dart' as foundation;

/// Voting logs are debug-only so release builds never emit sensitive metadata.
void debugPrint(String? message, {int? wrapWidth}) {
  if (!foundation.kDebugMode || message == null) return;
  foundation.debugPrint(message, wrapWidth: wrapWidth);
}
