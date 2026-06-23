import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show AnyhowException;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/send_failure.dart';

void main() {
  group('classifySendFailure', () {
    test('parses stable coded failures', () {
      expect(
        classifySendFailure('sync_in_progress|have 1, need 2'),
        SendFailureKind.syncInProgress,
      );
      expect(
        classifySendFailure('scan_required|anchor unavailable'),
        SendFailureKind.scanRequired,
      );
      expect(
        classifySendFailure('insufficient_funds|have 1, need 2'),
        SendFailureKind.insufficientFunds,
      );
    });

    test('reads the coded marker from a real FRB AnyhowException', () {
      // FRB decodes a Rust `Err(String)` into AnyhowException(message)
      // (frb_generated.dart: `return AnyhowException(raw as String)`), so this is the
      // actual runtime type the send/swap call sites catch. Pins the .message branch.
      expect(
        classifySendFailure(
          AnyhowException('sync_in_progress|Propose failed: Insufficient balance'),
        ),
        SendFailureKind.syncInProgress,
      );
      expect(
        classifySendFailure(
          AnyhowException('insufficient_funds|Propose failed: Insufficient balance'),
        ),
        SendFailureKind.insufficientFunds,
      );
    });

    test('does not classify legacy free-form insufficient text', () {
      expect(
        classifySendFailure('Propose failed: insufficient funds'),
        SendFailureKind.unknown,
      );
    });

    test('treats sync and scan failures as waiting for sync', () {
      expect(SendFailureKind.syncInProgress.isWaitingForSync, isTrue);
      expect(SendFailureKind.scanRequired.isWaitingForSync, isTrue);
      expect(SendFailureKind.insufficientFunds.isWaitingForSync, isFalse);
      expect(SendFailureKind.unknown.isWaitingForSync, isFalse);
    });
  });
}
