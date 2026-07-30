import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/formatting/sync_status_label.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  test('migration entry restarts a sync from an older foreground epoch', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: true,
        activeSyncForegroundEpoch: 2,
        currentForegroundEpoch: 3,
      ),
      isTrue,
    );
  });

  test('migration entry joins a sync started in the current foreground', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: true,
        activeSyncForegroundEpoch: 3,
        currentForegroundEpoch: 3,
      ),
      isFalse,
    );
  });

  test('migration entry restarts a sync that began in background', () {
    expect(
      shouldRestartSyncForMigrationEntry(
        hasAttachedSync: true,
        activeSyncStartedInForeground: false,
        activeSyncForegroundEpoch: 3,
        currentForegroundEpoch: 3,
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

  test('in-flight progress exits quietly after notifier disposal', () async {
    final resolverStarted = Completer<void>();
    final dbPath = Completer<String>();
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async {
            resolverStarted.complete();
            return dbPath.future;
          }),
        ),
      ],
    );
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final handling = notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 20,
        percentage: 0.5,
        displayTargetPercentage: 0.5,
        displayTargetBlocks: 0,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    await resolverStarted.future;

    container.dispose();
    dbPath.complete('wallet.db');

    await expectLater(handling, completes);
  });

  test('in-flight progress cannot replace a newer sync failure', () async {
    final resolverStarted = Completer<void>();
    final dbPath = Completer<String>();
    late _LifecycleTestSyncNotifier notifier;
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        accountProvider.overrideWith(_ExistingAccountNotifier.new),
        syncProvider.overrideWith(
          () => notifier = _LifecycleTestSyncNotifier(() async {
            resolverStarted.complete();
            return dbPath.future;
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncProvider, (_, _) {});
    await container.read(syncProvider.future);

    final handling = notifier.handleSyncProgressForTesting(
      const SyncProgressEvent(
        scannedHeight: 10,
        chainTipHeight: 100,
        percentage: 0,
        displayTargetPercentage: 0,
        displayTargetBlocks: 0,
        isSyncing: true,
        isComplete: false,
        hasNewTx: false,
      ),
    );
    await resolverStarted.future;

    final failure = classifySyncFailure(StateError('sync failed'));
    notifier.replaceState(
      SyncState(
        accountUuid: _accountUuid,
        failure: failure,
        error: failure.rawMessage,
        lastSyncFailedAt: DateTime.utc(2026, 7, 29),
      ),
    );
    dbPath.complete('wallet.db');
    await handling;

    final current = container.read(syncProvider).requireValue;
    expect(
      SyncStatusLabel.from(current).label,
      'Syncing failed. Unknown error...',
    );
    expect(current.failure, same(failure));
    expect(current.isSyncing, isFalse);
  });
}

class _LifecycleTestSyncNotifier extends SyncNotifier {
  _LifecycleTestSyncNotifier(Future<String> Function() walletDbPathResolver)
    : super(walletDbPathResolver: walletDbPathResolver);

  @override
  Future<SyncState> build() async => SyncState();

  void replaceState(SyncState next) {
    state = AsyncData(next);
  }
}

const _accountUuid = 'account-1';

class _ExistingAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: _accountUuid, name: 'Account 1', order: 0)],
    activeAccountUuid: _accountUuid,
  );
}
