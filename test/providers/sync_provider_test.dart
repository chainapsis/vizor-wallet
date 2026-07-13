import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test(
    'sync failure records error before refreshing committed DB state',
    () async {
      final events = <String>[];
      final error = StateError('final enhancement failed');

      await recordSyncFailureAndRefreshCommittedState(
        error: error,
        recordFailure: (recorded) {
          expect(recorded, same(error));
          events.add('record');
        },
        refreshCommittedState: () async {
          events.add('refresh');
        },
        onRefreshError: (_, _) => fail('refresh should succeed'),
      );

      expect(events, ['record', 'refresh']);
    },
  );

  test(
    'sync failure remains recorded when committed-state refresh fails',
    () async {
      final events = <String>[];
      final error = StateError('sync failed');
      final refreshError = StateError('DB unavailable');

      await recordSyncFailureAndRefreshCommittedState(
        error: error,
        recordFailure: (_) => events.add('record'),
        refreshCommittedState: () async {
          events.add('refresh');
          throw refreshError;
        },
        onRefreshError: (recorded, _) {
          expect(recorded, same(refreshError));
          events.add('refresh-error');
        },
      );

      expect(events, ['record', 'refresh', 'refresh-error']);
    },
  );

  test('progress preserves only a failure recorded during its async wait', () {
    final oldFailure = classifySyncFailure(StateError('old failure'));
    final newFailure = classifySyncFailure(StateError('new failure'));
    final oldFailedAt = DateTime.utc(2026, 1, 1);
    final newFailedAt = DateTime.utc(2026, 1, 2);
    final beforeAwait = SyncState(
      failure: oldFailure,
      error: oldFailure.rawMessage,
      lastSyncFailedAt: oldFailedAt,
    );

    expect(
      syncFailureWasRecordedWhileProgressAwaited(
        beforeAwait: beforeAwait,
        current: beforeAwait,
      ),
      isFalse,
    );
    expect(
      syncFailureWasRecordedWhileProgressAwaited(
        beforeAwait: beforeAwait,
        current: SyncState(
          failure: newFailure,
          error: newFailure.rawMessage,
          lastSyncFailedAt: newFailedAt,
        ),
      ),
      isTrue,
    );
  });

  test(
    'clearCachedWalletDbPath forces the next DB path lookup to refresh',
    () async {
      final resolvedPaths = ['old-wallet.db', 'new-wallet.db'];
      var resolveCount = 0;
      final notifier = SyncNotifier(
        walletDbPathResolver: () async => resolvedPaths[resolveCount++],
      );

      expect(await notifier.resolveWalletDbPathForTesting(), 'old-wallet.db');
      expect(await notifier.resolveWalletDbPathForTesting(), 'old-wallet.db');
      expect(resolveCount, 1);

      notifier.clearCachedWalletDbPath();

      expect(await notifier.resolveWalletDbPathForTesting(), 'new-wallet.db');
      expect(resolveCount, 2);
    },
  );
}
