import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/private_state_sync/private_state_crypto.dart';
import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/private_state_sync_provider.dart'
    show privateStateRemoteStoreProvider;
import '../../../providers/rpc_endpoint_provider.dart';
import '../models/swap_models.dart';
import '../private_state/swap_private_history_document.dart';
import '../private_state/swap_private_history_sync.dart';
import '../private_state/swap_private_history_sync_metadata.dart';
import 'swap_activity_replica.dart';
import 'swap_activity_store.dart';

typedef FinalizedActivityArchiveAccountUuidLoader =
    Future<List<String>> Function();
typedef FinalizedActivityArchiveDbPathLoader = Future<String> Function();
typedef FinalizedActivityArchiveLocalAccountCleaner =
    Future<void> Function(String accountUuid);
typedef FinalizedActivityArchiveRetryDelaySampler = Duration Function();

enum _FinalizedActivityArchiveWorkKind { discover, publish }

class _FinalizedActivityArchiveWork {
  const _FinalizedActivityArchiveWork({
    required this.accountUuid,
    required this.historyKind,
    required this.workKind,
  });

  final String accountUuid;
  final SwapPrivateHistoryKind historyKind;
  final _FinalizedActivityArchiveWorkKind workKind;

  @override
  bool operator ==(Object other) =>
      other is _FinalizedActivityArchiveWork &&
      other.accountUuid == accountUuid &&
      other.historyKind == historyKind &&
      other.workKind == workKind;

  @override
  int get hashCode => Object.hash(accountUuid, historyKind, workKind);
}

const _finalizedActivityArchiveRetryBaseDelay = Duration(seconds: 30);
const _finalizedActivityArchiveRetryJitter = Duration(seconds: 15);

@visibleForTesting
Duration sampleFinalizedActivityArchiveRetryDelay(Random random) {
  final minimumMilliseconds =
      _finalizedActivityArchiveRetryBaseDelay.inMilliseconds -
      _finalizedActivityArchiveRetryJitter.inMilliseconds;
  final rangeMilliseconds =
      _finalizedActivityArchiveRetryJitter.inMilliseconds * 2;
  return Duration(
    milliseconds: minimumMilliseconds + random.nextInt(rangeMilliseconds + 1),
  );
}

final finalizedActivityArchiveMetadataStoreProvider =
    Provider<FinalizedActivityArchiveMetadataStore>((ref) {
      return AppSecureStoreFinalizedActivityArchiveMetadataStore(
        AppSecureStore.instance,
      );
    });

final finalizedActivityArchiveSyncProvider =
    Provider<FinalizedActivityArchiveSynchronizer?>((ref) {
      final remote = ref.watch(privateStateRemoteStoreProvider);
      if (remote == null) return null;
      return FinalizedActivityArchiveSync(
        repository: DefaultPrivateStateObjectRepository(
          crypto: const RustPrivateStateCrypto(),
          remote: remote,
        ),
        replica: ref.read(swapActivityReplicaProvider),
        metadataStore: ref.read(finalizedActivityArchiveMetadataStoreProvider),
      );
    });

final finalizedActivityArchiveDbPathLoaderProvider =
    Provider<FinalizedActivityArchiveDbPathLoader>((ref) => getWalletDbPath);

final finalizedActivityArchiveAccountUuidLoaderProvider =
    Provider<FinalizedActivityArchiveAccountUuidLoader>((ref) {
      return () async {
        final accountState = await ref.read(accountProvider.future);
        return accountState.accounts
            .map((account) => account.uuid)
            .toList(growable: false);
      };
    });

final finalizedActivityArchiveRetryDelayProvider =
    Provider<FinalizedActivityArchiveRetryDelaySampler>((ref) {
      final random = Random.secure();
      return () => sampleFinalizedActivityArchiveRetryDelay(random);
    });

class FinalizedActivityArchiveLifecycleCoordinator {
  FinalizedActivityArchiveLifecycleCoordinator({
    required FinalizedActivityArchiveSynchronizer synchronizer,
    required FinalizedActivityArchiveAccountUuidLoader accountUuidLoader,
    required FinalizedActivityArchiveDbPathLoader dbPathLoader,
    required String Function() networkLoader,
    required bool Function() isLocked,
    required FinalizedActivityArchiveMetadataStore metadataStore,
    required FinalizedActivityArchiveLocalAccountCleaner localAccountCleaner,
    required FinalizedActivityArchiveRetryDelaySampler retryDelaySampler,
  }) : _synchronizer = synchronizer,
       _accountUuidLoader = accountUuidLoader,
       _dbPathLoader = dbPathLoader,
       _networkLoader = networkLoader,
       _isLocked = isLocked,
       _metadataStore = metadataStore,
       _localAccountCleaner = localAccountCleaner,
       _retryDelaySampler = retryDelaySampler;

  final FinalizedActivityArchiveSynchronizer _synchronizer;
  final FinalizedActivityArchiveAccountUuidLoader _accountUuidLoader;
  final FinalizedActivityArchiveDbPathLoader _dbPathLoader;
  final String Function() _networkLoader;
  final bool Function() _isLocked;
  final FinalizedActivityArchiveMetadataStore _metadataStore;
  final FinalizedActivityArchiveLocalAccountCleaner _localAccountCleaner;
  final FinalizedActivityArchiveRetryDelaySampler _retryDelaySampler;
  final Set<_FinalizedActivityArchiveWork> _queuedWork = {};
  final Set<_FinalizedActivityArchiveWork> _retryWork = {};
  final Set<String> _revokedAccounts = {};
  Future<void>? _drainInFlight;
  Timer? _retryTimer;
  bool _retryAllRequested = false;
  bool _paused = false;
  bool _disposed = false;

  Future<void> synchronizeAll() async {
    if (_cannotRun) return;
    try {
      final accounts = await _accountUuidLoader();
      if (_cannotRun) return;
      for (final accountUuid in accounts) {
        if (_revokedAccounts.contains(accountUuid)) continue;
        _queueAccountDiscovery(accountUuid);
      }
      await _drain();
    } catch (error, stackTrace) {
      _logFailure('account discovery', error, stackTrace);
      if (!_cannotRun) _scheduleAllRetry();
    }
  }

  Future<void> synchronizeAccount(String accountUuid) async {
    if (_cannotRun ||
        accountUuid.isEmpty ||
        _revokedAccounts.contains(accountUuid)) {
      return;
    }
    _queueAccountDiscovery(accountUuid);
    await _drain();
  }

  Future<void> handleAccountSetChanged({
    required Set<String> previousAccounts,
    required Set<String> currentAccounts,
  }) {
    final addedAccounts = currentAccounts.difference(previousAccounts);
    _revokedAccounts.removeAll(addedAccounts);

    for (final accountUuid in previousAccounts.difference(currentAccounts)) {
      _revokeAccount(accountUuid);
    }

    if (currentAccounts.isEmpty) {
      _queuedWork.clear();
      _retryWork.clear();
      _retryAllRequested = false;
      _retryTimer?.cancel();
      _retryTimer = null;
    } else {
      _cancelRetryTimerIfIdle();
    }
    return synchronizeAll();
  }

  Future<void> handleReplicaChange(SwapActivityReplicaChange change) async {
    switch (change.source) {
      case SwapActivityReplicaChangeSource.localMutation:
      case SwapActivityReplicaChangeSource.providerRefresh:
        if (_cannotRun || _revokedAccounts.contains(change.accountUuid)) {
          return;
        }
        final kinds = {
          for (final record in change.changedRecords)
            if (record.status == SwapIntentStatus.complete ||
                record.status == SwapIntentStatus.refunded)
              record.payMode
                  ? SwapPrivateHistoryKind.pay
                  : SwapPrivateHistoryKind.swap,
        };
        for (final kind in kinds) {
          _queuedWork.add(
            _FinalizedActivityArchiveWork(
              accountUuid: change.accountUuid,
              historyKind: kind,
              workKind: _FinalizedActivityArchiveWorkKind.publish,
            ),
          );
        }
        if (kinds.isNotEmpty) await _drain();
      case SwapActivityReplicaChangeSource.remoteReconcile:
        return;
      case SwapActivityReplicaChangeSource.localAccountDeletion:
        _revokeAccount(change.accountUuid);
        final inFlight = _drainInFlight;
        if (inFlight != null) await inFlight;
        try {
          await _localAccountCleaner(change.accountUuid);
        } catch (error, stackTrace) {
          _logFailure('deleted-account local cleanup', error, stackTrace);
        }
        try {
          await _metadataStore.deleteForAccount(
            accountUuid: change.accountUuid,
          );
        } catch (error, stackTrace) {
          _logFailure('deleted-account metadata cleanup', error, stackTrace);
        }
    }
  }

  void pause() {
    _paused = true;
    _queuedWork.clear();
    _retryWork.clear();
    _retryAllRequested = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> resume() {
    if (_disposed) return Future.value();
    _paused = false;
    return synchronizeAll();
  }

  void dispose() {
    _disposed = true;
    pause();
  }

  Future<void> _drain() {
    final existing = _drainInFlight;
    if (existing != null) return existing;
    late final Future<void> run;
    run = _drainQueued().whenComplete(() {
      if (identical(_drainInFlight, run)) _drainInFlight = null;
      if (!_cannotRun && _queuedWork.isNotEmpty) {
        unawaited(_drain());
      }
    });
    _drainInFlight = run;
    return run;
  }

  Future<void> _drainQueued() async {
    final failed = <_FinalizedActivityArchiveWork>{};
    while (!_cannotRun && _queuedWork.isNotEmpty) {
      final work = _nextQueuedWork();
      _queuedWork.remove(work);
      if (_revokedAccounts.contains(work.accountUuid)) continue;
      try {
        final dbPath = await _dbPathLoader();
        final account = PrivateStateAccount(
          dbPath: dbPath,
          network: _networkLoader(),
          accountUuid: work.accountUuid,
        );
        if (_cannotRun || _revokedAccounts.contains(work.accountUuid)) {
          return;
        }
        switch (work.workKind) {
          case _FinalizedActivityArchiveWorkKind.discover:
            await _synchronizer.synchronize(
              account: account,
              kind: work.historyKind,
            );
          case _FinalizedActivityArchiveWorkKind.publish:
            await _synchronizer.publishPending(
              account: account,
              kind: work.historyKind,
            );
        }
        _retryWork.remove(work);
      } catch (error, stackTrace) {
        if (_revokedAccounts.contains(work.accountUuid)) continue;
        failed.add(work);
        _logFailure(
          'account=${work.accountUuid} kind=${work.historyKind.wireName} '
          'operation=${work.workKind.name}',
          error,
          stackTrace,
        );
      }
    }
    if (failed.isNotEmpty && !_cannotRun) {
      _scheduleRetry(failed);
    }
  }

  _FinalizedActivityArchiveWork _nextQueuedWork() => _queuedWork.firstWhere(
    (work) => work.workKind == _FinalizedActivityArchiveWorkKind.publish,
    orElse: () => _queuedWork.first,
  );

  void _queueAccountDiscovery(String accountUuid) {
    for (final kind in SwapPrivateHistoryKind.values) {
      _queuedWork.add(
        _FinalizedActivityArchiveWork(
          accountUuid: accountUuid,
          historyKind: kind,
          workKind: _FinalizedActivityArchiveWorkKind.discover,
        ),
      );
    }
  }

  void _scheduleRetry(Set<_FinalizedActivityArchiveWork> work) {
    _retryWork.addAll(work);
    _ensureRetryTimer();
  }

  void _revokeAccount(String accountUuid) {
    _revokedAccounts.add(accountUuid);
    _queuedWork.removeWhere((work) => work.accountUuid == accountUuid);
    _retryWork.removeWhere((work) => work.accountUuid == accountUuid);
    _cancelRetryTimerIfIdle();
  }

  void _cancelRetryTimerIfIdle() {
    if (_retryWork.isNotEmpty || _retryAllRequested) return;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleAllRetry() {
    _retryAllRequested = true;
    _ensureRetryTimer();
  }

  void _ensureRetryTimer() {
    if (_retryTimer?.isActive ?? false) return;
    final sampledDelay = _retryDelaySampler();
    final retryDelay = sampledDelay.isNegative ? Duration.zero : sampledDelay;
    debugPrint(
      '[private-state] retry scheduled feature=activity '
      'delay=${retryDelay.inMilliseconds}ms',
    );
    _retryTimer = Timer(retryDelay, () {
      _retryTimer = null;
      if (!_cannotRun) {
        _queuedWork.addAll(
          _retryWork.where(
            (work) => !_revokedAccounts.contains(work.accountUuid),
          ),
        );
        _retryWork.clear();
        final retryAll = _retryAllRequested;
        _retryAllRequested = false;
        if (retryAll) {
          unawaited(synchronizeAll());
        } else {
          unawaited(_drain());
        }
      }
    });
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    debugPrint(
      '[zcash] Finalized activity archive failed '
      '$operation: $error\n$stackTrace',
    );
  }

  bool get _cannotRun => _disposed || _paused || _isLocked();
}

final finalizedActivityArchiveLifecycleProvider =
    Provider<FinalizedActivityArchiveLifecycleCoordinator?>((ref) {
      final synchronizer = ref.watch(finalizedActivityArchiveSyncProvider);
      if (synchronizer == null) return null;
      final coordinator = FinalizedActivityArchiveLifecycleCoordinator(
        synchronizer: synchronizer,
        accountUuidLoader: ref.read(
          finalizedActivityArchiveAccountUuidLoaderProvider,
        ),
        dbPathLoader: ref.read(finalizedActivityArchiveDbPathLoaderProvider),
        networkLoader: () => ref.read(rpcEndpointProvider).networkName,
        isLocked: () => ref.read(appSecurityProvider).requiresUnlock,
        metadataStore: ref.read(finalizedActivityArchiveMetadataStoreProvider),
        localAccountCleaner: (accountUuid) => ref
            .read(swapActivityStoreProvider)
            .deleteForAccount(accountUuid: accountUuid),
        retryDelaySampler: ref.read(finalizedActivityArchiveRetryDelayProvider),
      );

      ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
        if (next.requiresUnlock) {
          coordinator.pause();
        } else if (previous?.requiresUnlock == true) {
          unawaited(coordinator.resume());
        }
      });
      ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
        final previousIds = previous?.value?.accounts
            .map((account) => account.uuid)
            .toSet();
        final nextIds = next.value?.accounts
            .map((account) => account.uuid)
            .toSet();
        final nextActiveAccountUuid = next.value?.activeAccountUuid;
        if (nextIds != null && !_setEquals(previousIds, nextIds)) {
          unawaited(
            coordinator.handleAccountSetChanged(
              previousAccounts: previousIds ?? const {},
              currentAccounts: nextIds,
            ),
          );
        } else if (previous?.value?.activeAccountUuid !=
                nextActiveAccountUuid &&
            nextActiveAccountUuid != null) {
          unawaited(coordinator.synchronizeAccount(nextActiveAccountUuid));
        }
      });
      ref.listen<SwapActivityReplicaChange?>(
        swapActivityReplicaChangeProvider,
        (_, next) {
          if (next != null) unawaited(coordinator.handleReplicaChange(next));
        },
      );
      final lifecycle = AppLifecycleListener(
        onResume: () => unawaited(coordinator.resume()),
        onHide: coordinator.pause,
      );
      ref.onDispose(() {
        lifecycle.dispose();
        coordinator.dispose();
      });
      unawaited(coordinator.synchronizeAll());
      return coordinator;
    });

bool _setEquals(Set<String>? left, Set<String>? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  return left.containsAll(right);
}
