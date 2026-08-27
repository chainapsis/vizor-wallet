import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/private_state_sync/private_state_crypto.dart';
import '../../../core/private_state_sync/private_state_models.dart';
import '../../../core/private_state_sync/private_state_object_repository.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/voting/voting_service_providers.dart'
    show privateStateRemoteStoreProvider;
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

final finalizedActivityArchiveRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
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
    required Duration retryDelay,
  }) : _synchronizer = synchronizer,
       _accountUuidLoader = accountUuidLoader,
       _dbPathLoader = dbPathLoader,
       _networkLoader = networkLoader,
       _isLocked = isLocked,
       _metadataStore = metadataStore,
       _localAccountCleaner = localAccountCleaner,
       _retryDelay = retryDelay.isNegative ? Duration.zero : retryDelay;

  final FinalizedActivityArchiveSynchronizer _synchronizer;
  final FinalizedActivityArchiveAccountUuidLoader _accountUuidLoader;
  final FinalizedActivityArchiveDbPathLoader _dbPathLoader;
  final String Function() _networkLoader;
  final bool Function() _isLocked;
  final FinalizedActivityArchiveMetadataStore _metadataStore;
  final FinalizedActivityArchiveLocalAccountCleaner _localAccountCleaner;
  final Duration _retryDelay;
  final Set<String> _queuedAccounts = {};
  final Set<String> _retryAccounts = {};
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
      _queuedAccounts.addAll(
        accounts.where((account) => !_revokedAccounts.contains(account)),
      );
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
    _queuedAccounts.add(accountUuid);
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
      _queuedAccounts.clear();
      _retryAccounts.clear();
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
        if (change.changedRecords.any(
          (record) =>
              record.status == SwapIntentStatus.complete ||
              record.status == SwapIntentStatus.refunded,
        )) {
          await synchronizeAccount(change.accountUuid);
        }
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
    _queuedAccounts.clear();
    _retryAccounts.clear();
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
      if (!_cannotRun && _queuedAccounts.isNotEmpty) {
        unawaited(_drain());
      }
    });
    _drainInFlight = run;
    return run;
  }

  Future<void> _drainQueued() async {
    final failed = <String>{};
    while (!_cannotRun && _queuedAccounts.isNotEmpty) {
      final accountUuid = _queuedAccounts.first;
      _queuedAccounts.remove(accountUuid);
      if (_revokedAccounts.contains(accountUuid)) continue;
      try {
        final dbPath = await _dbPathLoader();
        final account = PrivateStateAccount(
          dbPath: dbPath,
          network: _networkLoader(),
          accountUuid: accountUuid,
        );
        for (final kind in SwapPrivateHistoryKind.values) {
          if (_cannotRun || _revokedAccounts.contains(accountUuid)) {
            return;
          }
          await _synchronizer.synchronize(account: account, kind: kind);
        }
        _retryAccounts.remove(accountUuid);
      } catch (error, stackTrace) {
        if (_revokedAccounts.contains(accountUuid)) continue;
        failed.add(accountUuid);
        _logFailure('account=$accountUuid', error, stackTrace);
      }
    }
    if (failed.isNotEmpty && !_cannotRun) {
      _scheduleRetry(failed);
    }
  }

  void _scheduleRetry(Set<String> accounts) {
    _retryAccounts.addAll(accounts);
    _ensureRetryTimer();
  }

  void _revokeAccount(String accountUuid) {
    _revokedAccounts.add(accountUuid);
    _queuedAccounts.remove(accountUuid);
    _retryAccounts.remove(accountUuid);
    _cancelRetryTimerIfIdle();
  }

  void _cancelRetryTimerIfIdle() {
    if (_retryAccounts.isNotEmpty || _retryAllRequested) return;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _scheduleAllRetry() {
    _retryAllRequested = true;
    _ensureRetryTimer();
  }

  void _ensureRetryTimer() {
    if (_retryTimer?.isActive ?? false) return;
    debugPrint(
      '[private-state] retry scheduled feature=activity '
      'delay=${_retryDelay.inSeconds}s',
    );
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      if (!_cannotRun) {
        _queuedAccounts.addAll(
          _retryAccounts.where(
            (account) => !_revokedAccounts.contains(account),
          ),
        );
        _retryAccounts.clear();
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
        retryDelay: ref.read(finalizedActivityArchiveRetryDelayProvider),
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
