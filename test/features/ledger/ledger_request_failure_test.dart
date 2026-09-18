import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

void main() {
  for (final failure in LedgerMobileFailure.values) {
    test('typed $failure takes precedence over diagnostic text', () {
      expect(
        LedgerRequestFailure.fromError(
          LedgerMobileException(failure, 'Request rejected: 6985'),
        ),
        failure == LedgerMobileFailure.rejected
            ? LedgerRequestFailure.declined
            : LedgerRequestFailure.other,
      );
    });
  }

  test('nested connection and readiness wrappers preserve the cause', () {
    const rejection = LedgerMobileException(
      LedgerMobileFailure.rejected,
      'Device response',
    );
    expect(
      LedgerRequestFailure.fromError(
        const LedgerConnectionRequiredException(
          'Connection failed',
          cause: LedgerAppReadinessException(
            LedgerAppReadinessFailure.unavailable,
            'App failed',
            cause: rejection,
          ),
        ),
      ),
      LedgerRequestFailure.declined,
    );
    expect(
      LedgerRequestFailure.fromError(
        const LedgerAppReadinessException(
          LedgerAppReadinessFailure.rejected,
          'Rejected',
          cause: LedgerMobileException(
            LedgerMobileFailure.cancelled,
            'Cancelled locally',
          ),
        ),
      ),
      LedgerRequestFailure.other,
    );
  });

  test('readiness rejection without a cause remains declined', () {
    expect(
      LedgerRequestFailure.fromError(
        const LedgerAppReadinessException(
          LedgerAppReadinessFailure.rejected,
          'Device response',
        ),
      ),
      LedgerRequestFailure.declined,
    );
  });

  for (final message in ['Transaction rejected', 'APDU status 0x6985']) {
    test('text-only APDU response is a rejection estimate: $message', () {
      expect(
        LedgerRequestFailure.fromError(StateError(message)),
        LedgerRequestFailure.declined,
      );
    });
  }

  test('unknown failures do not invent a rejection', () {
    expect(
      LedgerRequestFailure.fromError(StateError('Device response missing')),
      LedgerRequestFailure.other,
    );
    expect(
      LedgerRequestFailure.fromError(
        const LedgerConnectionRequiredException('Connection failed'),
      ),
      LedgerRequestFailure.other,
    );
  });
}
