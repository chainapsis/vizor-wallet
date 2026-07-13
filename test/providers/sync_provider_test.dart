import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/background_sync_delegate.dart';

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

  test('stale progress merges data without reviving a failed sync', () {
    final failure = classifySyncFailure(StateError('sync failed'));
    final failedAt = DateTime.utc(2026, 1, 2);
    final failureState = SyncState(
      accountUuid: 'account',
      isSyncing: false,
      isBackgroundMode: false,
      percentage: 0.4,
      displayPercentage: 0.4,
      displayTargetPercentage: 0.4,
      displayTargetBlocks: 0,
      scannedHeight: 40,
      chainTipHeight: 100,
      failure: failure,
      error: failure.rawMessage,
      lastSyncFailedAt: failedAt,
      phase: '',
    );
    final staleProgress = SyncState(
      accountUuid: 'account',
      hasBalanceData: true,
      hasRecentTransactionsData: true,
      isSyncing: true,
      percentage: 0.5,
      displayPercentage: 0.5,
      displayTargetPercentage: 0.6,
      displayTargetBlocks: 10,
      scannedHeight: 50,
      chainTipHeight: 100,
      orchardBalance: BigInt.from(42),
      totalBalance: BigInt.from(42),
      phase: 'scan',
    );

    final merged = mergeProgressDataIntoConcurrentFailure(
      currentFailureState: failureState,
      progressState: staleProgress,
    );

    expect(merged.isSyncing, isFalse);
    expect(merged.percentage, 0.4);
    expect(merged.displayTargetBlocks, 0);
    expect(merged.scannedHeight, 40);
    expect(merged.phase, isEmpty);
    expect(merged.failure, same(failure));
    expect(merged.lastSyncFailedAt, failedAt);
    expect(merged.hasAccountScopedData, isTrue);
    expect(merged.orchardBalance, BigInt.from(42));
    expect(merged.totalBalance, BigInt.from(42));
  });

  test('stale progress cannot restart smoothing after a sync failure', () {
    const progress = SyncProgressEvent(
      scannedHeight: 50,
      chainTipHeight: 100,
      percentage: 0.5,
      displayTargetPercentage: 0.6,
      displayTargetBlocks: 10,
      isSyncing: true,
      isComplete: false,
      hasNewTx: true,
      phase: 'scan',
    );

    expect(
      shouldSmoothSyncProgress(
        event: progress,
        preserveConcurrentFailure: true,
        isBackgroundDelegateActive: false,
      ),
      isFalse,
    );
    expect(
      shouldSmoothSyncProgress(
        event: progress,
        preserveConcurrentFailure: false,
        isBackgroundDelegateActive: false,
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
