import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';

void main() {
  test('classifies transient network failures', () {
    final failure = classifySyncFailure(
      'network: get_latest_block: status: DeadlineExceeded',
    );

    expect(failure.kind, SyncFailureKind.network);
    expect(failure.showSettingsAction, isFalse);
  });

  test('classifies malformed endpoint failures as settings action', () {
    final failure = classifySyncFailure('network: invalid URL: bad uri');

    expect(failure.kind, SyncFailureKind.endpoint);
    expect(failure.showSettingsAction, isTrue);
    expect(failure.actionLabel, 'Settings');
  });

  test('classifies temporary database lock', () {
    final failure = classifySyncFailure(
      'other: scan: SQLite lock contention: database is locked',
    );

    expect(failure.kind, SyncFailureKind.databaseBusy);
  });

  test('classifies fatal database failures', () {
    final failure = classifySyncFailure('db: open wallet DB: disk full');

    expect(failure.kind, SyncFailureKind.databaseFatal);
  });

  test('classifies parse failures', () {
    final failure = classifySyncFailure('parse: bad tree state');

    expect(failure.kind, SyncFailureKind.parseFatal);
  });

  test('classifies a failed Tor route as a paused state with a Tor retry', () {
    for (final raw in const [
      'network: network privacy blocked lightwalletd: Tor connection failed',
      'Tor could not connect. Check your internet connection and try again.',
      'network: Tor is enabled but unavailable',
    ]) {
      final failure = classifySyncFailure(raw);

      expect(failure.kind, SyncFailureKind.torUnavailable, reason: raw);
      expect(failure.retriesTorRoute, isTrue, reason: raw);
      expect(failure.showSettingsAction, isFalse, reason: raw);
      expect(failure.actionLabel, 'Retry', reason: raw);
      expect(
        failure.userMessage,
        "Tor couldn't connect. Retry, or turn Tor off in Settings.",
      );
    }
  });

  test('a Tor bootstrap the user abandoned stays a transient failure', () {
    for (final raw in const [
      'network: Tor gRPC connect failed: Tor was turned off while it was connecting',
      'network: Tor wait cancelled',
    ]) {
      final failure = classifySyncFailure(raw);

      expect(failure.kind, SyncFailureKind.network, reason: raw);
      expect(failure.retriesTorRoute, isFalse, reason: raw);
    }
  });

  test('classifies chain recovery failures', () {
    final failure = classifySyncFailure(
      'chain continuity broken at height 123: PrevHashMismatch',
    );

    expect(failure.kind, SyncFailureKind.chainRecovery);
  });

  test('classifies unknown failures', () {
    final failure = classifySyncFailure(Exception('unexpected failure'));

    expect(failure.kind, SyncFailureKind.unknown);
    expect(failure.rawMessage, 'unexpected failure');
    expect(failure.actionLabel, 'Retry');
  });
}
