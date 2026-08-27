import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account_provider.dart';
import '../app_security_provider.dart';
import '../../core/private_state_sync/private_state_models.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_private_state_sync.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';

final votingPrivateStateRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});

class VotingPrivateRoundCandidate {
  const VotingPrivateRoundCandidate({
    required this.roundId,
    required this.proposalIds,
  });

  final String roundId;
  final List<int> proposalIds;
}

class VotingLocalCompletionState {
  const VotingLocalCompletionState({required this.blocksRemote, this.record});

  final bool blocksRemote;
  final VotingCompletionRecord? record;
}

class VotingPrivateCompletionSweep {
  const VotingPrivateCompletionSweep({
    required VotingPrivateStateSync sync,
    required Future<List<String>> Function() accountUuidLoader,
    required Future<String> Function() dbPathLoader,
    required String Function() networkLoader,
    required Future<List<VotingPrivateRoundCandidate>> Function() roundLoader,
    required Future<VotingLocalCompletionState> Function({
      required String dbPath,
      required String accountUuid,
      required VotingPrivateRoundCandidate round,
    })
    localCompletionLoader,
  }) : _sync = sync,
       _accountUuidLoader = accountUuidLoader,
       _dbPathLoader = dbPathLoader,
       _networkLoader = networkLoader,
       _roundLoader = roundLoader,
       _localCompletionLoader = localCompletionLoader;

  final VotingPrivateStateSync _sync;
  final Future<List<String>> Function() _accountUuidLoader;
  final Future<String> Function() _dbPathLoader;
  final String Function() _networkLoader;
  final Future<List<VotingPrivateRoundCandidate>> Function() _roundLoader;
  final Future<VotingLocalCompletionState> Function({
    required String dbPath,
    required String accountUuid,
    required VotingPrivateRoundCandidate round,
  })
  _localCompletionLoader;

  Future<void> synchronizeAll() async {
    final accounts = await _accountUuidLoader();
    if (accounts.isEmpty) {
      debugPrint('[private-state] voting sync complete accounts=0 rounds=0');
      return;
    }
    final rounds = await _roundLoader();
    debugPrint(
      '[private-state] voting sync start '
      'accounts=${accounts.length} rounds=${rounds.length}',
    );
    if (rounds.isEmpty) {
      debugPrint(
        '[private-state] voting sync complete '
        'accounts=${accounts.length} rounds=0',
      );
      return;
    }
    final dbPath = await _dbPathLoader();
    final network = _networkLoader();
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final accountUuid in accounts) {
      final account = PrivateStateAccount(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
      for (final round in rounds) {
        try {
          final local = await _localCompletionLoader(
            dbPath: dbPath,
            accountUuid: accountUuid,
            round: round,
          );
          final record = local.record;
          if (record != null) {
            await _sync.publishCompletion(account: account, record: record);
          } else if (!local.blocksRemote) {
            await _sync.readCompletion(
              account: account,
              roundId: round.roundId,
            );
          }
        } catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
          debugPrint(
            '[zcash] Voting: private completion sweep failed '
            'account=$accountUuid round=${round.roundId}: $error',
          );
        }
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
    debugPrint(
      '[private-state] voting sync complete '
      'accounts=${accounts.length} rounds=${rounds.length}',
    );
  }
}

class VotingPrivateStateLifecycleCoordinator {
  VotingPrivateStateLifecycleCoordinator({
    required Future<String?> Function() activeAccountUuidLoader,
    required Future<void> Function() refresh,
    required bool Function() isLocked,
    required Duration retryDelay,
  }) : _activeAccountUuidLoader = activeAccountUuidLoader,
       _refresh = refresh,
       _isLocked = isLocked,
       _retryDelay = retryDelay.isNegative ? Duration.zero : retryDelay;

  final Future<String?> Function() _activeAccountUuidLoader;
  final Future<void> Function() _refresh;
  final bool Function() _isLocked;
  final Duration _retryDelay;
  Future<void>? _inFlight;
  Timer? _retryTimer;
  bool _queued = false;
  bool _paused = false;
  bool _disposed = false;

  Future<void> synchronize() {
    if (_cannotRun) return Future.value();
    final running = _inFlight;
    if (running != null) {
      _queued = true;
      return running;
    }
    late final Future<void> run;
    run = _run().whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
      if (_queued && !_cannotRun) {
        _queued = false;
        unawaited(synchronize());
      }
    });
    _inFlight = run;
    return run;
  }

  Future<void> _run() async {
    try {
      final accountUuid = await _activeAccountUuidLoader();
      if (_cannotRun || accountUuid == null || accountUuid.isEmpty) return;
      await _refresh();
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (error, stackTrace) {
      debugPrint(
        '[zcash] Voting: private completion background sync failed: '
        '$error\n$stackTrace',
      );
      _scheduleRetry();
    }
  }

  void pause() {
    _paused = true;
    _queued = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> resume() {
    if (_disposed) return Future.value();
    _paused = false;
    return synchronize();
  }

  void dispose() {
    _disposed = true;
    pause();
  }

  void _scheduleRetry() {
    if (_cannotRun || (_retryTimer?.isActive ?? false)) return;
    debugPrint(
      '[private-state] retry scheduled feature=voting '
      'delay=${_retryDelay.inSeconds}s',
    );
    _retryTimer = Timer(_retryDelay, () {
      _retryTimer = null;
      unawaited(synchronize());
    });
  }

  bool get _cannotRun => _disposed || _paused || _isLocked();
}

final votingPrivateStateLifecycleProvider =
    Provider<VotingPrivateStateLifecycleCoordinator?>((ref) {
      final sync = ref.watch(votingPrivateStateSyncProvider);
      if (sync == null) return null;
      final recovery = ref.read(votingRecoveryServiceProvider);
      final sweep = VotingPrivateCompletionSweep(
        sync: sync,
        accountUuidLoader: () async {
          final state = await ref.read(accountProvider.future);
          return state.accounts.map((account) => account.uuid).toList();
        },
        dbPathLoader: ref.read(votingWalletDbPathProvider),
        networkLoader: () =>
            ref.read(votingRpcEndpointConfigProvider).networkName,
        roundLoader: () async {
          final config = await ref.read(votingConfigProvider.future);
          final api = ref.read(votingApiClientProvider(config.apiServers));
          final rounds = await api.listRounds();
          final candidates = <VotingPrivateRoundCandidate>[];
          for (final round in rounds) {
            if (!config.isRoundAuthenticated(round.roundId)) continue;
            var proposalIds = proposalsFromJson(
              round.rawJson,
            ).map((proposal) => proposal.id).toList();
            if (proposalIds.isEmpty) {
              final status = await api.getRoundStatus(round.roundId);
              proposalIds = proposalsFromJson(
                status.rawJson,
              ).map((proposal) => proposal.id).toList();
            }
            candidates.add(
              VotingPrivateRoundCandidate(
                roundId: round.roundId,
                proposalIds: proposalIds,
              ),
            );
          }
          return candidates;
        },
        localCompletionLoader:
            ({required dbPath, required accountUuid, required round}) async {
              final plan = await recovery.loadRoundPlan(
                dbPath: dbPath,
                accountUuid: accountUuid,
                roundId: round.roundId,
                proposalIds: round.proposalIds,
              );
              return VotingLocalCompletionState(
                blocksRemote: hasBlockingRoundRecoveryWork(plan),
                record: VotingCompletionRecord.fromRoundPlan(
                  roundId: round.roundId,
                  roundPlan: plan,
                ),
              );
            },
      );
      final coordinator = VotingPrivateStateLifecycleCoordinator(
        activeAccountUuidLoader: ref.read(votingActiveAccountUuidProvider),
        isLocked: () => ref.read(appSecurityProvider).requiresUnlock,
        retryDelay: ref.read(votingPrivateStateRetryDelayProvider),
        refresh: sweep.synchronizeAll,
      );

      ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
        if (next.requiresUnlock) {
          coordinator.pause();
        } else if (previous?.requiresUnlock == true) {
          unawaited(coordinator.resume());
        }
      });
      ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
        if (previous?.value?.activeAccountUuid !=
            next.value?.activeAccountUuid) {
          unawaited(coordinator.synchronize());
        }
      });
      final lifecycle = AppLifecycleListener(
        onResume: () => unawaited(coordinator.resume()),
        onHide: coordinator.pause,
      );
      ref.onDispose(() {
        lifecycle.dispose();
        coordinator.dispose();
      });
      unawaited(coordinator.synchronize());
      return coordinator;
    });
