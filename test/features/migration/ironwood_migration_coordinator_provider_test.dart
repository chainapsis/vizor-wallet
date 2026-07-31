@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_background_credential_store.dart';
import 'package:zcash_wallet/src/features/migration/services/ironwood_migration_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _softwareUuid = 'software-account';
const _hardwareUuid = 'hardware-account';
const _endpoint = RpcEndpointConfig(
  networkName: 'test',
  lightwalletdUrl: 'https://example.test:443',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('same-session permit advances software signing', () async {
    final statuses = {
      _softwareUuid: _status('ready_to_migrate'),
      _hardwareUuid: _status('ready_to_migrate'),
    };
    final softwareStarts = <String>[];
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: softwareStarts,
      broadcasts: broadcasts,
    );
    addTearDown(container.dispose);

    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantChildProofBatchPermit(_softwareUuid);
    await coordinator.refreshNow(forceAdvance: true);

    expect(softwareStarts, [_softwareUuid]);
    expect(broadcasts, [_softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .childProofBatchPermits,
      isNot(contains(_softwareUuid)),
    );
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .statuses[_hardwareUuid]
          ?.phase,
      'ready_to_migrate',
    );
  });

  test(
    'Keystone signing can clear proof approval without pausing foreground',
    () async {
      final container = _container(
        statuses: {
          _softwareUuid: _status('complete', activeRunId: null),
          _hardwareUuid: _status(
            'ready_to_migrate',
            signedChildPcztCount: 1,
            nextActionHeight: 1_100,
          ),
        },
        softwareStarts: [],
        broadcasts: [],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      coordinator.grantChildProofBatchPermit(_hardwareUuid);
      coordinator.clearChildProofBatchPermit(_hardwareUuid);

      final state = container.read(ironwoodMigrationCoordinatorProvider);
      expect(state.foregroundProgressPermits, contains(_hardwareUuid));
      expect(state.childProofBatchPermits, isNot(contains(_hardwareUuid)));
    },
  );

  test(
    'reconciles a scheduled migration even when local height is behind',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final softwareStarts = <String>[];
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: softwareStarts,
        broadcasts: broadcasts,
        syncState: SyncState(scannedHeight: 999, chainTipHeight: 1_001),
      );
      addTearDown(container.dispose);

      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.grantForegroundProgressPermit(_softwareUuid);
      await coordinator.refreshNow(forceAdvance: true);

      expect(broadcasts, [_softwareUuid]);
      expect(softwareStarts, isEmpty);
    },
  );

  test(
    'refreshes the active home balance after a migration confirmation',
    () async {
      final statuses = {
        _softwareUuid: _status('waiting_migration_confirmations'),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        syncState: SyncState(),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      final sync = container.read(syncProvider.notifier) as FakeSyncNotifier;
      expect(sync.balanceRefreshes, 0);

      statuses[_softwareUuid] = _status(
        'waiting_migration_confirmations',
        confirmedTxCount: 1,
      );
      await coordinator.refreshNow();
      expect(sync.balanceRefreshes, 1);

      await coordinator.refreshNow();
      expect(sync.balanceRefreshes, 1);
    },
  );

  test(
    'refreshes the active home balance after a successful store retry',
    () async {
      // Accepted-but-unstored rows stay `broadcasted`; a successful store-from-
      // raw only clears the durable storage-retry message. The coordinator must
      // still refresh SyncState so home no longer shows pre-store Orchard funds.
      const storageRetryMessage =
          'Migration transaction aa was accepted by lightwalletd, but local '
          'wallet storage failed: boom. Vizor will retry until local state is '
          'recorded.';
      final statuses = {
        _softwareUuid: _status(
          'waiting_migration_confirmations',
          broadcastedTxCount: 1,
          message: storageRetryMessage,
        ),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        syncState: SyncState(),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      final sync = container.read(syncProvider.notifier) as FakeSyncNotifier;
      expect(sync.balanceRefreshes, 0);

      statuses[_softwareUuid] = _status(
        'waiting_migration_confirmations',
        broadcastedTxCount: 1,
      );
      await coordinator.refreshNow();
      expect(sync.balanceRefreshes, 1);

      await coordinator.refreshNow();
      expect(sync.balanceRefreshes, 1);
    },
  );

  test('non-outbox mobile waits until a scheduled migration is due', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
      usesNativeOutbox: false,
      syncState: SyncState(scannedHeight: 999, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantForegroundProgressPermit(_softwareUuid);
    await coordinator.refreshNow();

    expect(broadcasts, isEmpty);
  });

  test(
    'non-outbox mobile advances waiting confirmations for store retry',
    () async {
      final statuses = {
        _softwareUuid: _status('waiting_migration_confirmations'),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: broadcasts,
        usesNativeOutbox: false,
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.grantForegroundProgressPermit(_softwareUuid);
      await coordinator.refreshNow();

      expect(broadcasts, [_softwareUuid]);
    },
  );

  test(
    'non-outbox mobile advances broadcast_scheduled for store retry before next due height',
    () async {
      final statuses = {
        _softwareUuid: _status(
          'broadcast_scheduled',
          broadcastedTxCount: 1,
          scheduledHeight: 1_200,
          scheduledStatus: 'scheduled',
          extraBroadcasts: [
            rust_sync.MigrationScheduledBroadcast(
              txidHex: 'accepted-unstored',
              valueZatoshi: BigInt.from(50000000),
              scheduledAtMs: 0,
              scheduledHeight: 1_000,
              status: 'broadcasted',
            ),
          ],
        ),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: broadcasts,
        usesNativeOutbox: false,
        // Tip is past the accepted part but before the later scheduled part.
        syncState: SyncState(scannedHeight: 1_050, chainTipHeight: 1_051),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.grantForegroundProgressPermit(_softwareUuid);
      await coordinator.refreshNow();

      expect(broadcasts, [_softwareUuid]);
    },
  );

  test('reentry refresh is read-only without a foreground permit', () async {
    final statuses = {
      _softwareUuid: _status(
        'broadcast_scheduled',
        signedChildPcztCount: 1,
        nextActionHeight: 1_000,
        proofReady: true,
      ),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final advances = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: advances,
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow(forceAdvance: true);

    expect(advances, isEmpty);
  });

  test('same-session permit broadcasts a due scheduled migration', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantForegroundProgressPermit(_softwareUuid);
    await coordinator.refreshNow();

    expect(broadcasts, [_softwareUuid]);
  });

  test(
    'manual retry runs again after an automatic attempt in flight',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final firstAttemptStarted = Completer<void>();
      final releaseFirstAttempt = Completer<void>();
      var attemptCount = 0;
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
        broadcast: (accountUuid) async {
          attemptCount++;
          if (attemptCount == 1) {
            firstAttemptStarted.complete();
            await releaseFirstAttempt.future;
          }
          return _result('broadcast_scheduled');
        },
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.grantForegroundProgressPermit(_softwareUuid);
      final automatic = coordinator.refreshNow();
      await firstAttemptStarted.future;
      final manual = coordinator.retry(_softwareUuid);
      await Future<void>.delayed(Duration.zero);
      expect(attemptCount, 1);

      releaseFirstAttempt.complete();
      await automatic;
      await manual;

      expect(attemptCount, 2);
    },
  );

  test('manual retry uses the due native outbox recovery lane', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final recoveries = <String>[];
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
      outboxRecoveries: recoveries,
      recoverOutbox: (_) async => throw StateError(
        'Ironwood migration credential is missing for the active run.',
      ),
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    await coordinator.refreshNow();
    recoveries.clear();

    await expectLater(
      coordinator.retry(_softwareUuid, status: statuses[_softwareUuid]),
      throwsA(isA<StateError>()),
    );

    expect(recoveries, [_softwareUuid]);
    expect(broadcasts, isEmpty);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_softwareUuid],
      contains('credential is missing for the active run'),
    );
  });

  test(
    'manual retry recovers a due outbox before sync reports a height',
    () async {
      // A status screen can be the first surface after a cold launch, so an
      // explicit retry can run before the first sync snapshot arrives. Treating
      // the unknown height as "not due" would route the user action back into the
      // ordinary advance that cannot restore a missing native outbox batch.
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final recoveries = <String>[];
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: broadcasts,
        outboxRecoveries: recoveries,
        recoverOutbox: (_) async => throw StateError(
          'Ironwood migration credential is missing for the active run.',
        ),
        syncState: SyncState(),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await expectLater(
        coordinator.retry(_softwareUuid, status: statuses[_softwareUuid]),
        throwsA(isA<StateError>()),
      );

      expect(recoveries, [_softwareUuid]);
      expect(broadcasts, isEmpty);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        contains('credential is missing for the active run'),
      );
    },
  );

  test('resumes proof preparation when its anchor height is scanned', () async {
    final statuses = {
      _softwareUuid: _status(
        'broadcast_scheduled',
        signedChildPcztCount: 1,
        nextActionHeight: 1_000,
        proofReady: true,
      ),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final advances = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: advances,
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantChildProofBatchPermit(_softwareUuid);
    await coordinator.refreshNow();

    expect(advances, [_softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .childProofBatchPermits,
      isNot(contains(_softwareUuid)),
    );
  });

  test('one explicit action advances only one child proof batch', () async {
    final statuses = {
      _softwareUuid: _status(
        'broadcast_scheduled',
        signedChildPcztCount: 16,
        nextActionHeight: 1_000,
        proofReady: true,
        scheduledHeight: 1_100,
      ),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final advances = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: advances,
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
      broadcast: (accountUuid) async {
        statuses[accountUuid] = _status(
          'broadcast_scheduled',
          signedChildPcztCount: 8,
          nextActionHeight: 1_000,
          proofReady: true,
          scheduledHeight: 1_100,
        );
        return _result('broadcast_scheduled');
      },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantChildProofBatchPermit(_softwareUuid);
    await coordinator.refreshNow();
    await coordinator.refreshNow(forceAdvance: true);

    expect(advances, [_softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .childProofBatchPermits,
      isNot(contains(_softwareUuid)),
    );
  });

  test(
    'resumes presigned Keystone proof preparation at its anchor height',
    () async {
      final statuses = {
        _softwareUuid: _status('complete', activeRunId: null),
        _hardwareUuid: _status(
          'ready_to_migrate',
          signedChildPcztCount: 1,
          nextActionHeight: 1_000,
          proofReady: true,
        ),
      };
      final advances = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: advances,
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.grantChildProofBatchPermit(_hardwareUuid);
      await coordinator.refreshNow();

      expect(advances, [_hardwareUuid]);
    },
  );

  test('does not prepare the next proof before its anchor height', () async {
    final statuses = {
      _softwareUuid: _status(
        'broadcast_scheduled',
        signedChildPcztCount: 1,
        nextActionHeight: 1_000,
      ),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final advances = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: advances,
      syncState: SyncState(scannedHeight: 999, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantChildProofBatchPermit(_softwareUuid);
    await coordinator.refreshNow();

    expect(advances, isEmpty);
  });

  test(
    'does not prepare a height-due proof until witness preflight passes',
    () async {
      final statuses = {
        _softwareUuid: _status(
          'broadcast_scheduled',
          signedChildPcztCount: 1,
          nextActionHeight: 1_000,
          proofReady: false,
        ),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final advances = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: advances,
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_001),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.grantChildProofBatchPermit(_softwareUuid);
      await coordinator.refreshNow();

      expect(advances, isEmpty);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .childProofBatchPermits,
        contains(_softwareUuid),
      );
    },
  );

  test('does not prepare proof before any wallet height is scanned', () async {
    final statuses = {
      _softwareUuid: _status(
        'broadcast_scheduled',
        signedChildPcztCount: 1,
        nextActionHeight: 1_000,
      ),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final advances = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: advances,
      syncState: SyncState(scannedHeight: 0, chainTipHeight: 1_001),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantChildProofBatchPermit(_softwareUuid);
    await coordinator.refreshNow();

    expect(advances, isEmpty);
  });

  test('explicit Keystone permit broadcasts a due migration', () async {
    final statuses = {
      _softwareUuid: _status('complete', activeRunId: null),
      _hardwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
    };
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantForegroundProgressPermit(_hardwareUuid);
    await coordinator.refreshNow();

    expect(broadcasts, [_hardwareUuid]);
  });

  test(
    'due native outbox recovers in foreground without a signing permit',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final outboxRecoveries = <String>[];
      final broadcasts = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: broadcasts,
        outboxRecoveries: outboxRecoveries,
        recoverOutbox: (accountUuid) async {
          statuses[accountUuid] = _status('waiting_migration_confirmations');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.accepted,
            observedHeight: 1_000,
          );
        },
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      await container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();

      expect(outboxRecoveries, [_softwareUuid]);
      expect(broadcasts, isEmpty);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .foregroundProgressPermits,
        isEmpty,
      );
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .statuses[_softwareUuid]
            ?.phase,
        'waiting_migration_confirmations',
      );
    },
  );

  test(
    'global outbox acceptance for another account retries the due account',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final recoveries = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        outboxRecoveries: recoveries,
        recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
          outcome: IronwoodMigrationOutboxRunOutcome.accepted,
          observedHeight: 1_000,
        ),
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      await coordinator.refreshNow();

      expect(recoveries, [_softwareUuid, _softwareUuid]);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        isNull,
      );
    },
  );

  test(
    'noWork is successful when reconciliation cleared the due status',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        recoverOutbox: (accountUuid) async {
          statuses[accountUuid] = _status('waiting_migration_confirmations');
          return const IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.noWork,
            observedHeight: 1_000,
          );
        },
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      await container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();

      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        isNull,
      );
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .statuses[_softwareUuid]
            ?.phase,
        'waiting_migration_confirmations',
      );
    },
  );

  test(
    'temporary native contention retries without showing an error',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final recoveries = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        outboxRecoveries: recoveries,
        recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
          outcome: IronwoodMigrationOutboxRunOutcome.temporarilyUnavailable,
        ),
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      await coordinator.refreshNow();

      expect(recoveries, [_softwareUuid, _softwareUuid]);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        isNull,
      );
    },
  );

  test(
    'global needs-user-action outcome is not attached to the due account',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final recoveries = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        outboxRecoveries: recoveries,
        recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
          outcome: IronwoodMigrationOutboxRunOutcome.needsUserAction,
          accountUuid: _hardwareUuid,
        ),
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      await coordinator.refreshNow();

      expect(recoveries, [_softwareUuid, _softwareUuid]);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        isNull,
      );
    },
  );

  test(
    'matching needs-user-action outcome becomes immediately actionable',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
          outcome: IronwoodMigrationOutboxRunOutcome.needsUserAction,
          accountUuid: _softwareUuid,
        ),
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);

      await container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();

      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        contains('needs user action'),
      );
    },
  );

  test('global waiting outcome does not throttle the due account', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final recoveries = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      outboxRecoveries: recoveries,
      recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
        outcome: IronwoodMigrationOutboxRunOutcome.waiting,
        nextHeight: 1_001,
        observedHeight: 1_000,
        accountUuid: _hardwareUuid,
      ),
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    await coordinator.refreshNow();
    await coordinator.refreshNow();

    expect(recoveries, [_softwareUuid, _softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_softwareUuid],
      isNull,
    );
  });

  test('matching waiting outcome throttles the due account', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final recoveries = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      outboxRecoveries: recoveries,
      recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
        outcome: IronwoodMigrationOutboxRunOutcome.waiting,
        nextHeight: 1_001,
        observedHeight: 1_000,
        accountUuid: _softwareUuid,
      ),
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    await coordinator.refreshNow();
    await coordinator.refreshNow();

    expect(recoveries, [_softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_softwareUuid],
      isNull,
    );
  });

  test(
    'matching native retry delay does not become a due-account error',
    () async {
      final statuses = {
        _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final recoveries = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        outboxRecoveries: recoveries,
        recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
          outcome: IronwoodMigrationOutboxRunOutcome.waiting,
          nextHeight: 1_000,
          observedHeight: 1_000,
          accountUuid: _softwareUuid,
          retryDelay: Duration(minutes: 1),
        ),
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      await coordinator.refreshNow();

      expect(recoveries, [_softwareUuid]);
      expect(
        container
            .read(ironwoodMigrationCoordinatorProvider)
            .errors[_softwareUuid],
        isNull,
      );
    },
  );

  test(
    'a new scheduled batch is not throttled by the previous batch',
    () async {
      final statuses = {
        _softwareUuid: _status(
          'broadcast_scheduled',
          scheduledHeight: 1_000,
          scheduledTxid: 'scheduled-tx-1',
        ),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final recoveries = <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        outboxRecoveries: recoveries,
        recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
          outcome: IronwoodMigrationOutboxRunOutcome.waiting,
          nextHeight: 1_000,
          observedHeight: 1_000,
          accountUuid: _softwareUuid,
          retryDelay: Duration(minutes: 10),
        ),
        syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(syncProvider.future);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      await coordinator.refreshNow();
      statuses[_softwareUuid] = _status(
        'broadcast_scheduled',
        scheduledHeight: 1_000,
        scheduledTxid: 'scheduled-tx-2',
      );
      await coordinator.refreshNow();

      expect(recoveries, [_softwareUuid, _softwareUuid]);
    },
  );

  test('due native outbox failure becomes immediately actionable', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final recoveries = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      outboxRecoveries: recoveries,
      recoverOutbox: (_) async => const IronwoodMigrationOutboxRunResult(
        outcome: IronwoodMigrationOutboxRunOutcome.noWork,
        observedHeight: 1_000,
      ),
      syncState: SyncState(scannedHeight: 1_000, chainTipHeight: 1_000),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow();

    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_softwareUuid],
      contains('not available in the background outbox'),
    );

    await container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow();

    expect(recoveries, [_softwareUuid, _softwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_softwareUuid],
      contains('not available in the background outbox'),
    );
  });

  test('one account failure does not block another account recovery', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
      _hardwareUuid: _status('broadcast_scheduled', scheduledHeight: 1_000),
    };
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
      syncState: SyncState(scannedHeight: 999, chainTipHeight: 1_001),
      broadcast: (accountUuid) async {
        if (accountUuid == _softwareUuid) {
          throw StateError('account outbox unavailable');
        }
        return _result('waiting_migration_confirmations');
      },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.read(syncProvider.future);

    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );
    coordinator.grantForegroundProgressPermit(_softwareUuid);
    coordinator.grantForegroundProgressPermit(_hardwareUuid);
    await coordinator.refreshNow();

    expect(broadcasts, [_softwareUuid, _hardwareUuid]);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .errors[_softwareUuid],
      contains('account outbox unavailable'),
    );
  });

  test(
    'batch status failure falls back to isolated per-account reads',
    () async {
      final statuses = {
        _softwareUuid: _status('waiting_denom_confirmations'),
        _hardwareUuid: _status('waiting_migration_confirmations'),
      };
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        isMobile: false,
        getStatuses:
            ({required dbPath, required network, required accountUuids}) async {
              throw StateError('wallet summary failed');
            },
        loadStatus: (accountUuid) async {
          if (accountUuid == _softwareUuid) {
            throw StateError('software status failed');
          }
          return statuses[accountUuid]!;
        },
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      await expectLater(
        container
            .read(ironwoodMigrationCoordinatorProvider.notifier)
            .refreshNow(),
        completes,
      );

      final state = container.read(ironwoodMigrationCoordinatorProvider);
      expect(state.errors[_softwareUuid], contains('software status failed'));
      expect(
        state.statuses[_hardwareUuid]?.phase,
        'waiting_migration_confirmations',
      );
      expect(state.errors[_hardwareUuid], isNull);
    },
  );

  test(
    'desktop sweep costs one batched status read, not one per account',
    () async {
      // The defect this pins: `status()` computes a full
      // `get_wallet_summary` across *every* account, so a per-account
      // sweep was quadratic in account count. Equivalence tests still
      // pass if that loop comes back — only the call count catches it.
      final statuses = {
        _softwareUuid: _status('waiting_denom_confirmations'),
        _hardwareUuid: _status('waiting_migration_confirmations'),
      };
      var batchedReads = 0;
      var singularReads = 0;
      var sweptAccountUuids = const <String>[];
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        isMobile: false,
        getStatuses:
            ({required dbPath, required network, required accountUuids}) async {
              batchedReads++;
              sweptAccountUuids = accountUuids;
              return [
                for (final uuid in accountUuids)
                  rust_sync.MigrationStatusEntry(
                    accountUuid: uuid,
                    status: statuses[uuid],
                  ),
              ];
            },
        loadStatus: (accountUuid) async {
          singularReads++;
          return statuses[accountUuid]!;
        },
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final notifier = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      // Drain whatever provider construction scheduled, so the counters
      // below describe exactly one pass.
      await notifier.refreshNow();
      batchedReads = 0;
      singularReads = 0;

      await notifier.refreshNow();

      expect(batchedReads, 1, reason: 'one summary per sweep');
      expect(
        singularReads,
        0,
        reason:
            'a singular status() call per account reintroduces the '
            'quadratic sweep',
      );
      expect(sweptAccountUuids, [_softwareUuid, _hardwareUuid]);
      final state = container.read(ironwoodMigrationCoordinatorProvider);
      expect(
        state.statuses[_softwareUuid]?.phase,
        'waiting_denom_confirmations',
      );
      expect(
        state.statuses[_hardwareUuid]?.phase,
        'waiting_migration_confirmations',
      );
      expect(state.errors, isEmpty);
    },
  );

  test('mobile sweep keeps the per-account status path', () async {
    // Batching is desktop-only on purpose: on mobile `status()` also
    // resolves credential context and drives preparation, so a batched
    // read would silently drop those side effects.
    final statuses = {
      _softwareUuid: _status('waiting_denom_confirmations'),
      _hardwareUuid: _status('waiting_migration_confirmations'),
    };
    var batchedReads = 0;
    var singularReads = 0;
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      isMobile: true,
      getStatuses:
          ({required dbPath, required network, required accountUuids}) async {
            batchedReads++;
            return [
              for (final uuid in accountUuids)
                rust_sync.MigrationStatusEntry(
                  accountUuid: uuid,
                  status: statuses[uuid],
                ),
            ];
          },
      loadStatus: (accountUuid) async {
        singularReads++;
        return statuses[accountUuid]!;
      },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final notifier = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    await notifier.refreshNow();
    batchedReads = 0;
    singularReads = 0;

    await notifier.refreshNow();

    expect(batchedReads, 0, reason: 'mobile must not take the batched path');
    expect(singularReads, statuses.length);
  });

  test(
    'coalesces a refresh requested while status loading is active',
    () async {
      final statuses = {
        _softwareUuid: _status('complete', activeRunId: null),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final firstStatusStarted = Completer<void>();
      final releaseFirstStatus = Completer<void>();
      var statusCallCount = 0;
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        loadStatus: (accountUuid) async {
          statusCallCount += 1;
          if (statusCallCount == 1) {
            firstStatusStarted.complete();
            await releaseFirstStatus.future;
          }
          return statuses[accountUuid]!;
        },
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final firstRefresh = container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow();
      await firstStatusStarted.future;
      var queuedRefreshCompleted = false;
      final queuedRefresh = container
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .refreshNow(forceAdvance: true)
          .whenComplete(() => queuedRefreshCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(queuedRefreshCompleted, isFalse);

      releaseFirstStatus.complete();
      await firstRefresh;
      await queuedRefresh;

      expect(queuedRefreshCompleted, isTrue);
      expect(statusCallCount, 4);
    },
  );

  test(
    'polling joins an active refresh without queuing another sweep',
    () async {
      final statuses = {
        _softwareUuid: _status('complete', activeRunId: null),
        _hardwareUuid: _status('complete', activeRunId: null),
      };
      final firstStatusStarted = Completer<void>();
      final releaseFirstStatus = Completer<void>();
      var statusCallCount = 0;
      final container = _container(
        statuses: statuses,
        softwareStarts: [],
        broadcasts: [],
        loadStatus: (accountUuid) async {
          statusCallCount += 1;
          if (statusCallCount == 1) {
            firstStatusStarted.complete();
            await releaseFirstStatus.future;
          }
          return statuses[accountUuid]!;
        },
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        ironwoodMigrationCoordinatorProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );

      final firstRefresh = coordinator.refreshNow();
      await firstStatusStarted.future;
      final pollingRefresh = coordinator.refreshForPolling();

      releaseFirstStatus.complete();
      await firstRefresh;
      await pollingRefresh;

      expect(statusCallCount, 2);
    },
  );

  testWidgets('polling waits 15 seconds after a slow sweep completes', (
    tester,
  ) async {
    final statuses = {
      _softwareUuid: _status('complete', activeRunId: null),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    Completer<void>? blockedStatus;
    Completer<void>? blockedStatusStarted;
    var statusCallCount = 0;
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      loadStatus: (accountUuid) async {
        statusCallCount += 1;
        final blocker = blockedStatus;
        if (blocker != null && !blocker.isCompleted) {
          blockedStatusStarted?.complete();
          await blocker.future;
        }
        return statuses[accountUuid]!;
      },
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IronwoodMigrationCoordinatorHost(child: SizedBox.shrink()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final initialStatusCallCount = statusCallCount;

    blockedStatus = Completer<void>();
    blockedStatusStarted = Completer<void>();
    await tester.pump(const Duration(seconds: 15));
    await blockedStatusStarted.future;
    expect(statusCallCount, initialStatusCallCount + 1);

    await tester.pump(const Duration(seconds: 30));
    expect(
      statusCallCount,
      initialStatusCallCount + 1,
      reason: 'a slow poll must not accumulate periodic timer ticks',
    );

    blockedStatus.complete();
    await tester.pump();
    await tester.pump();
    expect(statusCallCount, initialStatusCallCount + statuses.length);

    await tester.pump(const Duration(seconds: 14));
    expect(statusCallCount, initialStatusCallCount + statuses.length);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(statusCallCount, initialStatusCallCount + statuses.length * 2);
  });

  test('refreshes confirmation progress without broadcasting', () async {
    final statuses = {
      _softwareUuid: _status('waiting_migration_confirmations'),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final broadcasts = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: broadcasts,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    await coordinator.refreshNow(forceAdvance: true);
    statuses[_softwareUuid] = _status(
      'waiting_migration_confirmations',
      confirmedTxCount: 1,
    );
    await coordinator.refreshNow();

    expect(broadcasts, isEmpty);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .statuses[_softwareUuid]
          ?.confirmedTxCount,
      1,
    );
  });

  test('mobile coordinator pauses process work while hidden', () async {
    final statusCalls = <String>[];
    final container = _container(
      statuses: {
        _softwareUuid: _status('waiting_denom_confirmations'),
        _hardwareUuid: _status('complete', activeRunId: null),
      },
      softwareStarts: [],
      broadcasts: [],
      loadStatus: (accountUuid) async {
        statusCalls.add(accountUuid);
        return accountUuid == _softwareUuid
            ? _status('waiting_denom_confirmations')
            : _status('complete', activeRunId: null);
      },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    coordinator.grantForegroundProgressPermit(_softwareUuid);
    coordinator.setForeground(false);
    await coordinator.refreshNow(forceAdvance: true);

    expect(statusCalls, isEmpty);
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .foregroundProgressPermits,
      isEmpty,
    );
    expect(
      container
          .read(ironwoodMigrationCoordinatorProvider)
          .childProofBatchPermits,
      isEmpty,
    );
  });

  test('wallet reset clears process-local migration state', () async {
    final container = _container(
      statuses: {
        _softwareUuid: _status('waiting_denom_confirmations'),
        _hardwareUuid: _status('complete', activeRunId: null),
      },
      softwareStarts: [],
      broadcasts: [],
      mutableAccounts: true,
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    coordinator.grantForegroundProgressPermit(_softwareUuid);
    coordinator.grantChildProofBatchPermit(_softwareUuid);
    await coordinator.refreshNow();
    expect(
      container.read(ironwoodMigrationCoordinatorProvider).statuses,
      isNotEmpty,
    );

    (container.read(accountProvider.notifier) as _MutableAccountNotifier)
        .clearAccounts();
    await coordinator.refreshNow();

    final state = container.read(ironwoodMigrationCoordinatorProvider);
    expect(state.statuses, isEmpty);
    expect(state.errors, isEmpty);
    expect(state.advancingAccounts, isEmpty);
    expect(state.foregroundProgressPermits, isEmpty);
    expect(state.childProofBatchPermits, isEmpty);
  });

  test('wallet reset discards an in-flight status refresh', () async {
    final statuses = {
      _softwareUuid: _status('waiting_denom_confirmations'),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final statusStarted = Completer<void>();
    final releaseStatus = Completer<void>();
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      mutableAccounts: true,
      loadStatus: (accountUuid) async {
        if (!statusStarted.isCompleted) {
          statusStarted.complete();
          await releaseStatus.future;
        }
        return statuses[accountUuid]!;
      },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    final refresh = coordinator.refreshNow();
    await statusStarted.future;
    (container.read(accountProvider.notifier) as _MutableAccountNotifier)
        .clearAccounts();
    releaseStatus.complete();
    await refresh;

    expect(
      container.read(ironwoodMigrationCoordinatorProvider).statuses,
      isEmpty,
    );
  });

  testWidgets(
    'initial status refresh does not restart bound background preparation',
    (tester) async {
      final store = IronwoodMigrationBackgroundCredentialStore();
      await _bindBackgroundPreparationManifest(store);
      final preparationStarts = <String>[];
      final container = _container(
        statuses: {
          _softwareUuid: _status('waiting_denom_confirmations'),
          _hardwareUuid: _status('complete', activeRunId: null),
        },
        softwareStarts: [],
        broadcasts: [],
        syncState: SyncState(),
        isIOS: true,
        backgroundCredentialStore: store,
        backgroundPreparationStarts: preparationStarts,
        mutableAccounts: true,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IronwoodMigrationCoordinatorHost(
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();

      (container.read(syncProvider.notifier) as FakeSyncNotifier).emit(
        SyncState(scannedHeight: 1, chainTipHeight: 1),
      );
      (container.read(accountProvider.notifier) as _MutableAccountNotifier)
          .emitSameAccounts();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(preparationStarts, isEmpty);
    },
  );

  testWidgets('startup recovery records verified proof readiness explicitly', (
    tester,
  ) async {
    final proofReadinessRecords = <String>[];
    final container = _container(
      statuses: {
        _softwareUuid: _status(
          'ready_to_migrate',
          nextActionHeight: 1_000,
          proofReady: true,
        ),
        _hardwareUuid: _status('complete', activeRunId: null),
      },
      softwareStarts: [],
      broadcasts: [],
      syncState: SyncState(),
      isIOS: true,
      proofReadinessRecords: proofReadinessRecords,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IronwoodMigrationCoordinatorHost(child: SizedBox.shrink()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(proofReadinessRecords, [_softwareUuid]);
  });

  testWidgets('initial status refresh does not restart Keystone preparation', (
    tester,
  ) async {
    final store = IronwoodMigrationBackgroundCredentialStore();
    await _bindBackgroundPreparationManifest(store, accountUuid: _hardwareUuid);
    final preparationStarts = <String>[];
    final container = _container(
      statuses: {
        _softwareUuid: _status('complete', activeRunId: null),
        _hardwareUuid: _status('waiting_denom_confirmations'),
      },
      softwareStarts: [],
      broadcasts: [],
      syncState: SyncState(),
      isIOS: true,
      backgroundCredentialStore: store,
      backgroundPreparationStarts: preparationStarts,
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IronwoodMigrationCoordinatorHost(child: SizedBox.shrink()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(preparationStarts, isEmpty);
  });

  testWidgets(
    'unlock and foreground resume keep preparation paused for user action',
    (tester) async {
      final store = IronwoodMigrationBackgroundCredentialStore();
      await _bindBackgroundPreparationManifest(store);
      final preparationStarts = <String>[];
      final container = _container(
        statuses: {
          _softwareUuid: _status('waiting_denom_confirmations'),
          _hardwareUuid: _status('complete', activeRunId: null),
        },
        softwareStarts: [],
        broadcasts: [],
        syncState: SyncState(),
        isIOS: true,
        backgroundCredentialStore: store,
        backgroundPreparationStarts: preparationStarts,
        initialSecurityState: const AppSecurityState(
          isPasswordConfigured: true,
          isUnlocked: false,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IronwoodMigrationCoordinatorHost(
            child: SizedBox.shrink(),
          ),
        ),
      );
      await tester.pump();
      expect(preparationStarts, isEmpty);

      (container.read(appSecurityProvider.notifier) as _MutableSecurityNotifier)
          .setUnlocked(true);
      await tester.pump(const Duration(milliseconds: 50));

      final coordinator = container.read(
        ironwoodMigrationCoordinatorProvider.notifier,
      );
      coordinator.setForeground(false);
      coordinator.setForeground(true);
      await tester.pump(const Duration(milliseconds: 50));

      expect(preparationStarts, isEmpty);
    },
  );

  test('ignores a status result that completes after disposal', () async {
    final statuses = {
      _softwareUuid: _status('complete', activeRunId: null),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final statusStarted = Completer<void>();
    final releaseStatus = Completer<void>();
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      loadStatus: (accountUuid) async {
        if (!statusStarted.isCompleted) statusStarted.complete();
        await releaseStatus.future;
        return statuses[accountUuid]!;
      },
    );
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    final refresh = container
        .read(ironwoodMigrationCoordinatorProvider.notifier)
        .refreshNow();
    await statusStarted.future;

    subscription.close();
    container.dispose();
    releaseStatus.complete();

    await expectLater(refresh, completes);
  });

  test('duplicate stop callers await the same failing operation', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled'),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final stopStarted = Completer<void>();
    final releaseStop = Completer<void>();
    var stopCalls = 0;
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            stopCalls += 1;
            stopStarted.complete();
            await releaseStop.future;
            throw StateError('stop failed');
          },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    final first = coordinator.stop(accountUuid: _softwareUuid, runId: 'run-1');
    await stopStarted.future;
    final duplicate = coordinator.stop(
      accountUuid: _softwareUuid,
      runId: 'run-1',
    );
    final firstFailure = expectLater(first, throwsA(isA<StateError>()));
    final duplicateFailure = expectLater(duplicate, throwsA(isA<StateError>()));

    expect(stopCalls, 1);
    expect(
      container.read(ironwoodMigrationCoordinatorProvider).stoppingAccounts,
      contains(_softwareUuid),
    );

    releaseStop.complete();
    await Future.wait([firstFailure, duplicateFailure]);
    expect(stopCalls, 1);
  });

  test('stop requests for different runs execute serially', () async {
    final statuses = {
      _softwareUuid: _status('broadcast_scheduled'),
      _hardwareUuid: _status('complete', activeRunId: null),
    };
    final releaseOldRun = Completer<void>();
    final releaseNewRun = Completer<void>();
    final oldRunStarted = Completer<void>();
    final newRunStarted = Completer<void>();
    final stopCalls = <String>[];
    final container = _container(
      statuses: statuses,
      softwareStarts: [],
      broadcasts: [],
      usesNativeOutbox: false,
      stopMigrationRun:
          ({
            required dbPath,
            required lightwalletdUrl,
            required network,
            required accountUuid,
            required expectedRunId,
            required nativeAttemptedTxids,
          }) async {
            stopCalls.add(expectedRunId);
            if (expectedRunId == 'old-run') {
              oldRunStarted.complete();
              await releaseOldRun.future;
            } else {
              newRunStarted.complete();
              await releaseNewRun.future;
            }
          },
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      ironwoodMigrationCoordinatorProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final coordinator = container.read(
      ironwoodMigrationCoordinatorProvider.notifier,
    );

    final oldStop = coordinator.stop(
      accountUuid: _softwareUuid,
      runId: 'old-run',
    );
    await oldRunStarted.future;
    final newStop = coordinator.stop(
      accountUuid: _softwareUuid,
      runId: 'new-run',
    );

    expect(stopCalls, ['old-run']);
    releaseOldRun.complete();
    await oldStop;
    await newRunStarted.future;
    expect(stopCalls, ['old-run', 'new-run']);
    expect(
      container.read(ironwoodMigrationCoordinatorProvider).stoppingAccounts,
      contains(_softwareUuid),
    );

    releaseNewRun.complete();
    await newStop;
  });
}

ProviderContainer _container({
  required Map<String, rust_sync.MigrationStatus> statuses,
  required List<String> softwareStarts,
  required List<String> broadcasts,
  Future<rust_sync.MigrationStatus> Function(String accountUuid)? loadStatus,
  IronwoodMigrationStatusesGetter? getStatuses,
  Future<rust_sync.IronwoodMigrationResult> Function(String accountUuid)?
  broadcast,
  Future<IronwoodMigrationOutboxRunResult> Function(String accountUuid)?
  recoverOutbox,
  List<String>? outboxRecoveries,
  bool usesNativeOutbox = true,
  SyncState? syncState,
  bool isIOS = false,
  IronwoodMigrationBackgroundCredentialStore? backgroundCredentialStore,
  List<String>? backgroundPreparationStarts,
  List<String>? proofReadinessRecords,
  bool mutableAccounts = false,
  bool isMobile = true,
  AppSecurityState? initialSecurityState,
  IronwoodMigrationStopper? stopMigrationRun,
}) {
  final service = IronwoodMigrationService(
    getWalletDbPath: () async => '/tmp/wallet.db',
    getStatus:
        ({required dbPath, required network, required accountUuid}) async {
          return loadStatus?.call(accountUuid) ?? statuses[accountUuid]!;
        },
    getStatuses: getStatuses,
    getPrivatePlan:
        ({required dbPath, required network, required accountUuid}) async =>
            null,
    secureStore: AppSecureStore.testing(storage: const FlutterSecureStorage()),
    getEndpoint: () => _endpoint,
    getSessionPassword: () => 'test-password',
    isMacOS: () => true,
    isMobile: () => isMobile,
    isIOS: () => isIOS,
    supportsBackgroundMigration: () => usesNativeOutbox,
    isHardwareAccount: (uuid) => uuid == _hardwareUuid,
    backgroundCredentialStore:
        backgroundCredentialStore ?? _BoundCredentialStore(),
    startBackgroundPreparation: backgroundPreparationStarts == null
        ? null
        : () async {
            backgroundPreparationStarts.add(_softwareUuid);
            return true;
          },
    recordVerifiedProofReadiness: proofReadinessRecords == null
        ? null
        : ({
            required network,
            required accountUuid,
            required runId,
            required observedHeight,
          }) async {
            proofReadinessRecords.add(accountUuid);
            return true;
          },
    scheduleBackgroundMigration: () async => true,
    recoverDueMigrationOutbox:
        ({required network, required accountUuid}) async {
          outboxRecoveries?.add(accountUuid);
          if (recoverOutbox != null) return recoverOutbox(accountUuid);
          return IronwoodMigrationOutboxRunResult(
            outcome: IronwoodMigrationOutboxRunOutcome.waiting,
            nextHeight: 1_001,
            observedHeight: 1_000,
            accountUuid: accountUuid,
          );
        },
    broadcastDueMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
        }) async {
          broadcasts.add(accountUuid);
          if (broadcast != null) return broadcast(accountUuid);
          final current = statuses[accountUuid]!;
          if (current.phase == 'broadcast_scheduled') {
            statuses[accountUuid] = _status('waiting_migration_confirmations');
            return _result('waiting_migration_confirmations');
          }
          return _result(current.phase);
        },
    startMacosSoftwareMigration:
        ({
          required dbPath,
          required lightwalletdUrl,
          required network,
          required accountUuid,
          required password,
          required saltBase64,
          required approvedSchedule,
        }) async {
          softwareStarts.add(accountUuid);
          statuses[accountUuid] = _status('broadcast_scheduled');
          return _result('broadcast_scheduled');
        },
    stopMigrationRun: stopMigrationRun,
  );

  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      if (mutableAccounts)
        accountProvider.overrideWith(_MutableAccountNotifier.new),
      if (initialSecurityState != null)
        appSecurityProvider.overrideWith(
          () => _MutableSecurityNotifier(initialSecurityState),
        ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(syncState ?? SyncState()),
      ),
      ironwoodMigrationServiceProvider.overrideWithValue(service),
    ],
  );
}

Future<void> _bindBackgroundPreparationManifest(
  IronwoodMigrationBackgroundCredentialStore store, {
  String accountUuid = _softwareUuid,
}) async {
  await store.prepare(
    network: _endpoint.networkName,
    accountUuid: accountUuid,
    dbPath: '/tmp/wallet.db',
    lightwalletdUrl: _endpoint.normalizedLightwalletdUrl,
  );
  await store.bindExpectedRunId(
    network: _endpoint.networkName,
    accountUuid: accountUuid,
    expectedRunId: 'run-1',
  );
}

class _MutableAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => _bootstrap().initialAccountState;

  void emitSameAccounts() {
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(accounts: List<AccountInfo>.of(current.accounts)),
    );
  }

  void clearAccounts() {
    state = const AsyncData(AccountState());
  }
}

class _MutableSecurityNotifier extends AppSecurityNotifier {
  _MutableSecurityNotifier(this.initialState);

  final AppSecurityState initialState;

  @override
  AppSecurityState build() => initialState;

  void setUnlocked(bool value) {
    state = state.copyWith(isUnlocked: value);
  }
}

class _BoundCredentialStore extends IronwoodMigrationBackgroundCredentialStore {
  @override
  Future<IronwoodMigrationBackgroundCredentialManifest?> read({
    required String network,
    required String accountUuid,
  }) async {
    return IronwoodMigrationBackgroundCredentialManifest(
      version: 1,
      network: network,
      accountUuid: accountUuid,
      dbPath: '/tmp/wallet.db',
      lightwalletdUrl: _endpoint.normalizedLightwalletdUrl,
      credentialHex:
          '0000000000000000000000000000000000000000000000000000000000000000',
      saltBase64: 'AAAAAAAAAAAAAAAAAAAAAA==',
      expectedRunId: 'run-1',
    );
  }

  @override
  Future<bool> bindExpectedRunId({
    required String network,
    required String accountUuid,
    required String expectedRunId,
  }) async {
    return false;
  }

  @override
  Future<void> delete({
    required String network,
    required String accountUuid,
  }) async {}
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: _softwareUuid,
          name: 'Software',
          order: 0,
          isSeedAnchor: true,
        ),
        AccountInfo(
          uuid: _hardwareUuid,
          name: 'Keystone',
          order: 1,
          isHardware: true,
        ),
      ],
      activeAccountUuid: _softwareUuid,
      activeAddress: 'u1test',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: _endpoint.networkName,
    rpcEndpointConfig: _endpoint,
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

rust_sync.MigrationStatus _status(
  String phase, {
  String? activeRunId = 'run-1',
  int confirmedTxCount = 0,
  int broadcastedTxCount = 0,
  int? scheduledHeight,
  String scheduledTxid = 'scheduled-tx',
  String scheduledStatus = 'scheduled',
  List<rust_sync.MigrationScheduledBroadcast> extraBroadcasts = const [],
  int signedChildPcztCount = 0,
  int? nextActionHeight,
  bool? proofReady,
  String? message,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList([100000000]),
    preparedNoteCount: 1,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    denominationSplitCompletedCount: 1,
    denominationSplitTotalCount: 1,
    pendingTxCount: 1,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: confirmedTxCount,
    totalCount: 1,
    signedChildPcztCount: signedChildPcztCount,
    pendingSplitStageCount: 0,
    message: message,
    canAbandon: false,
    signingBatchLimit: 35,
    scheduleMeanDelayBlocks: 144,
    scheduleMaxDelayBlocks: 576,
    nextActionHeight: nextActionHeight,
    proofReady: proofReady,
    scheduledBroadcasts: [
      if (scheduledHeight != null)
        rust_sync.MigrationScheduledBroadcast(
          txidHex: scheduledTxid,
          valueZatoshi: BigInt.from(100000000),
          scheduledAtMs: 0,
          scheduledHeight: scheduledHeight,
          status: scheduledStatus,
        ),
      ...extraBroadcasts,
    ],
    parts: const [],
  );
}

rust_sync.IronwoodMigrationResult _result(String status) {
  return rust_sync.IronwoodMigrationResult(
    txids: '',
    status: status,
    broadcastedCount: 0,
    totalCount: 1,
    feeZatoshi: BigInt.zero,
    migratedZatoshi: BigInt.from(100000000),
  );
}
