import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';

void main() {
  test('classifies transient network failures as auto retrying', () {
    final failure = classifySyncFailure(
      'network: get_latest_block: status: DeadlineExceeded',
    );

    expect(failure.kind, SyncFailureKind.network);
    expect(failure.isAutoRetrying, isTrue);
    expect(failure.canManualRetry, isTrue);
    expect(failure.showSettingsAction, isFalse);
  });

  test('classifies malformed endpoint failures as settings action', () {
    final failure = classifySyncFailure('network: invalid URL: bad uri');

    expect(failure.kind, SyncFailureKind.endpoint);
    expect(failure.isAutoRetrying, isFalse);
    expect(failure.canManualRetry, isFalse);
    expect(failure.showSettingsAction, isTrue);
    expect(failure.actionLabel, 'Settings');
  });

  test('classifies temporary database lock as auto retrying', () {
    final failure = classifySyncFailure(
      'other: scan: SQLite lock contention: database is locked',
    );

    expect(failure.kind, SyncFailureKind.databaseBusy);
    expect(failure.isAutoRetrying, isTrue);
  });

  test('classifies fatal database failures without auto retry', () {
    final failure = classifySyncFailure('db: open wallet DB: disk full');

    expect(failure.kind, SyncFailureKind.databaseFatal);
    expect(failure.isAutoRetrying, isFalse);
    expect(failure.canManualRetry, isTrue);
  });

  test('classifies parse failures without auto retry', () {
    final failure = classifySyncFailure('parse: bad tree state');

    expect(failure.kind, SyncFailureKind.parseFatal);
    expect(failure.isAutoRetrying, isFalse);
  });

  test('classifies chain recovery failures as auto retrying', () {
    final failure = classifySyncFailure(
      'chain continuity broken at height 123: PrevHashMismatch',
    );

    expect(failure.kind, SyncFailureKind.chainRecovery);
    expect(failure.isAutoRetrying, isTrue);
  });

  test('classifies unknown failures as retryable fallback', () {
    final failure = classifySyncFailure(Exception('unexpected failure'));

    expect(failure.kind, SyncFailureKind.unknown);
    expect(failure.rawMessage, 'unexpected failure');
    expect(failure.isAutoRetrying, isTrue);
    expect(failure.actionLabel, 'Retry');
  });
}
