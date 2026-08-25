import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/private_state_sync/private_state_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_document.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync.dart';
import 'package:zcash_wallet/src/features/swap/private_state/swap_private_history_sync_metadata.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_replica.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_private_history_sync_provider.dart';

void main() {
  test(
    'startup synchronizes both namespaces for every existing account',
    () async {
      final synchronizer = _RecordingSynchronizer();
      final coordinator = _coordinator(
        synchronizer: synchronizer,
        accountUuids: ['account-a', 'account-b'],
      );
      addTearDown(coordinator.dispose);

      await coordinator.synchronizeAll();

      expect(
        synchronizer.calls.map(
          (call) => '${call.account.accountUuid}:${call.kind.wireName}',
        ),
        ['account-a:swap', 'account-a:pay', 'account-b:swap', 'account-b:pay'],
      );
      expect(synchronizer.calls.first.account.dbPath, '/wallet.db');
      expect(synchronizer.calls.first.account.network, 'main');
    },
  );

  test('lock pauses work and an explicit unlock pass resumes it', () async {
    var locked = true;
    final synchronizer = _RecordingSynchronizer();
    final coordinator = _coordinator(
      synchronizer: synchronizer,
      accountUuids: ['account-a'],
      isLocked: () => locked,
    );
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeAll();
    expect(synchronizer.calls, isEmpty);

    locked = false;
    await coordinator.synchronizeAll();
    expect(synchronizer.calls, hasLength(2));
  });

  test(
    'local changes upload, remote changes do not loop, deletion clears metadata',
    () async {
      final synchronizer = _RecordingSynchronizer();
      final metadata = _MemoryMetadataStore();
      final cleanedAccounts = <String>[];
      final coordinator = _coordinator(
        synchronizer: synchronizer,
        accountUuids: const [],
        metadataStore: metadata,
        localAccountCleaner: (account) async => cleanedAccounts.add(account),
      );
      addTearDown(coordinator.dispose);

      await coordinator.handleReplicaChange(
        _change(SwapActivityReplicaChangeSource.localMutation),
      );
      expect(synchronizer.calls, hasLength(2));

      await coordinator.handleReplicaChange(
        _change(SwapActivityReplicaChangeSource.remoteReconcile),
      );
      expect(synchronizer.calls, hasLength(2));

      await coordinator.handleReplicaChange(
        _change(SwapActivityReplicaChangeSource.localAccountDeletion),
      );
      expect(metadata.deletedAccounts, ['account-a']);
      expect(cleanedAccounts, ['account-a']);
    },
  );

  test('account deletion fences and cleans up an in-flight restore', () async {
    final firstCallStarted = Completer<void>();
    final releaseFirstCall = Completer<void>();
    final cleanedAccounts = <String>[];
    final synchronizer = _RecordingSynchronizer(
      firstCallStarted: firstCallStarted,
      releaseFirstCall: releaseFirstCall,
    );
    final coordinator = _coordinator(
      synchronizer: synchronizer,
      accountUuids: const [],
      localAccountCleaner: (account) async => cleanedAccounts.add(account),
    );
    addTearDown(coordinator.dispose);

    final sync = coordinator.synchronizeAccount('account-a');
    await firstCallStarted.future;
    final deletion = coordinator.handleReplicaChange(
      _change(SwapActivityReplicaChangeSource.localAccountDeletion),
    );
    releaseFirstCall.complete();
    await Future.wait([sync, deletion]);

    expect(cleanedAccounts, ['account-a']);
    expect(synchronizer.calls, hasLength(1));
    await coordinator.synchronizeAccount('account-a');
    expect(synchronizer.calls, hasLength(1));
  });

  test(
    'pause prevents an active drain from starting the next namespace',
    () async {
      final firstCallStarted = Completer<void>();
      final releaseFirstCall = Completer<void>();
      final synchronizer = _RecordingSynchronizer(
        firstCallStarted: firstCallStarted,
        releaseFirstCall: releaseFirstCall,
      );
      final coordinator = _coordinator(
        synchronizer: synchronizer,
        accountUuids: ['account-a'],
      );
      addTearDown(coordinator.dispose);

      final sync = coordinator.synchronizeAll();
      await firstCallStarted.future;
      coordinator.pause();
      releaseFirstCall.complete();
      await sync;

      expect(synchronizer.calls, hasLength(1));
    },
  );

  test('a failed pass is retried after the configured delay', () async {
    final completed = Completer<void>();
    final synchronizer = _RecordingSynchronizer(
      failFirstCall: true,
      onCall: (count) {
        if (count == 3 && !completed.isCompleted) completed.complete();
      },
    );
    final coordinator = _coordinator(
      synchronizer: synchronizer,
      accountUuids: const [],
      retryDelay: Duration.zero,
    );
    addTearDown(coordinator.dispose);

    await coordinator.synchronizeAccount('account-a');
    await completed.future.timeout(const Duration(seconds: 1));

    expect(synchronizer.calls.map((call) => call.kind), [
      SwapPrivateHistoryKind.swap,
      SwapPrivateHistoryKind.swap,
      SwapPrivateHistoryKind.pay,
    ]);
  });
}

SwapPrivateHistoryLifecycleCoordinator _coordinator({
  required _RecordingSynchronizer synchronizer,
  required List<String> accountUuids,
  _MemoryMetadataStore? metadataStore,
  SwapPrivateHistoryLocalAccountCleaner? localAccountCleaner,
  bool Function()? isLocked,
  Duration retryDelay = const Duration(seconds: 30),
}) {
  return SwapPrivateHistoryLifecycleCoordinator(
    synchronizer: synchronizer,
    accountUuidLoader: () async => accountUuids,
    dbPathLoader: () async => '/wallet.db',
    networkLoader: () => 'main',
    isLocked: isLocked ?? () => false,
    metadataStore: metadataStore ?? _MemoryMetadataStore(),
    localAccountCleaner: localAccountCleaner ?? (_) async {},
    retryDelay: retryDelay,
  );
}

SwapActivityReplicaChange _change(SwapActivityReplicaChangeSource source) {
  return SwapActivityReplicaChange(
    accountUuid: 'account-a',
    source: source,
    records: const <SwapIntentRecord>[],
  );
}

class _SyncCall {
  const _SyncCall(this.account, this.kind);

  final PrivateStateAccount account;
  final SwapPrivateHistoryKind kind;
}

class _RecordingSynchronizer implements SwapPrivateHistorySynchronizer {
  _RecordingSynchronizer({
    this.failFirstCall = false,
    this.onCall,
    this.firstCallStarted,
    this.releaseFirstCall,
  });

  final bool failFirstCall;
  final void Function(int count)? onCall;
  final Completer<void>? firstCallStarted;
  final Completer<void>? releaseFirstCall;
  final List<_SyncCall> calls = [];
  final List<SwapIntentRecord> deletedRecords = [];

  @override
  Future<void> recordLocalDeletions({
    required String accountUuid,
    required Iterable<SwapIntentRecord> records,
  }) async {
    deletedRecords.addAll(records);
  }

  @override
  Future<SwapPrivateHistorySyncResult> synchronize({
    required PrivateStateAccount account,
    required SwapPrivateHistoryKind kind,
  }) async {
    calls.add(_SyncCall(account, kind));
    onCall?.call(calls.length);
    if (calls.length == 1 && releaseFirstCall != null) {
      firstCallStarted?.complete();
      await releaseFirstCall!.future;
    }
    if (failFirstCall && calls.length == 1) throw StateError('offline');
    return SwapPrivateHistorySyncResult(
      records: const [],
      kind: kind,
      remoteVersion: null,
      remoteWritten: false,
      truncated: false,
    );
  }
}

class _MemoryMetadataStore implements SwapPrivateHistorySyncMetadataStore {
  final List<String> deletedAccounts = [];

  @override
  Future<void> addTombstones({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required Map<String, DateTime> tombstones,
  }) async {}

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    deletedAccounts.add(accountUuid);
  }

  @override
  Future<SwapPrivateHistorySyncMetadata?> load({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
  }) async => null;

  @override
  Future<void> save({
    required String accountUuid,
    required SwapPrivateHistoryKind kind,
    required SwapPrivateHistorySyncMetadata metadata,
  }) async {}
}
