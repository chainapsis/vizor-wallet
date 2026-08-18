import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';
import '../../rust/api/voting.dart' as rust_api;
import '../account_provider.dart';
import '../app_security_provider.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';
import 'voting_state.dart';

typedef VotingPendingShareRoundLoader =
    Future<List<rust_api.ApiPendingShareRound>> Function({
      required String dbPath,
      required List<String> accountUuids,
    });

typedef VotingAuthenticatedRoundIdsLoader = Future<Set<String>> Function();

/// Delay before retrying a failed pending-share discovery pass.
final votingPendingShareDiscoveryRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 15);
});

/// Loads durable unconfirmed share keys without creating a second state store.
@visibleForTesting
final votingPendingShareRoundLoaderProvider =
    Provider<VotingPendingShareRoundLoader>((ref) {
      return ({required dbPath, required accountUuids}) {
        return rust_api.listPendingShareRounds(
          dbPath: dbPath,
          accountUuids: accountUuids,
        );
      };
    });

/// Limits restored sessions to rounds authenticated by the current config.
@visibleForTesting
final votingAuthenticatedRoundIdsLoaderProvider =
    Provider<VotingAuthenticatedRoundIdsLoader>((ref) {
      return () async {
        final config = await ref.read(votingConfigProvider.future);
        return {for (final round in config.authenticatedRounds) round.roundId};
      };
    });

class VotingShareTrackingCoordinatorState {
  const VotingShareTrackingCoordinatorState({
    this.isRefreshing = false,
    this.trackedRoundCount = 0,
    this.lastError,
  });

  final bool isRefreshing;
  final int trackedRoundCount;
  final Object? lastError;
}

/// Restores and retains pending helper-share checks independently of vote UI.
///
/// The crate sidecar remains the durable source of truth. This coordinator runs
/// one pass on app launch and resume, while retained sessions run their normal
/// status and retry timers until the OS suspends the process.
class VotingShareTrackingCoordinatorNotifier
    extends Notifier<VotingShareTrackingCoordinatorState> {
  final Map<
    VotingSessionKey,
    ProviderSubscription<AsyncValue<VotingSessionState>>
  >
  _sessions = {};
  Future<void>? _refreshInFlight;
  Timer? _discoveryRetryTimer;
  bool _refreshQueued = false;
  bool _configRefreshQueued = false;
  bool _allTrackingQuiesced = false;
  final Set<String> _quiescedAccountUuids = {};

  @override
  VotingShareTrackingCoordinatorState build() {
    ref.onDispose(() {
      _cancelDiscoveryRetry();
      _closeAllSessions();
    });
    ref.listen<int>(votingConfigResolutionRevisionProvider, (previous, next) {
      if (previous != next) unawaited(refresh());
    });
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final previousIds = {
        for (final account
            in previous?.value?.accounts ?? const <AccountInfo>[])
          account.uuid,
      };
      final nextIds = {
        for (final account in next.value?.accounts ?? const <AccountInfo>[])
          account.uuid,
      };
      if (!setEquals(previousIds, nextIds)) unawaited(refresh());
    });
    ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
      if (next.requiresUnlock) {
        _cancelDiscoveryRetry();
        _closeAllSessions();
        _finishRefresh();
      } else if (previous?.requiresUnlock == true) {
        unawaited(refresh());
      }
    });
    return const VotingShareTrackingCoordinatorState();
  }

  /// Runs one discovery pass and coalesces concurrent triggers into a trailing
  /// pass. Resume callers may also rearm an existing dynamic config provider.
  Future<void> refresh({bool refreshConfig = false}) {
    _refreshQueued = true;
    _configRefreshQueued |= refreshConfig;
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    late final Future<void> refresh;
    refresh = _drainRefreshQueue().whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  /// Retains a completed submission session before its mutation guard drops.
  ///
  /// The synchronous ownership transfer closes the gap where account deletion
  /// could begin before durable discovery had inserted the session to drain.
  void retainSubmittedSession(VotingSessionKey key) {
    _sessions.putIfAbsent(key, () => _listenToSession(key));
    _finishRefresh();
    unawaited(refresh());
  }

  Future<void> _drainRefreshQueue() async {
    final checkedKeys = <VotingSessionKey>{};
    while (_refreshQueued) {
      _refreshQueued = false;
      final refreshConfig = _configRefreshQueued;
      _configRefreshQueued = false;
      await _refreshOnce(
        refreshConfig: refreshConfig,
        checkedKeys: checkedKeys,
      );
    }
  }

  Future<void> _refreshOnce({
    required bool refreshConfig,
    required Set<VotingSessionKey> checkedKeys,
  }) async {
    _cancelDiscoveryRetry();
    state = VotingShareTrackingCoordinatorState(
      isRefreshing: true,
      trackedRoundCount: _sessions.length,
    );
    if (_allTrackingQuiesced) {
      _closeAllSessions();
      _finishRefresh();
      return;
    }
    if (_pauseWhileLocked()) return;
    Object? firstError;
    try {
      final accountState = await ref.read(accountProvider.future);
      final accountUuids = accountState.accounts
          .map((account) => account.uuid)
          .where((accountUuid) => !_isTrackingQuiesced(accountUuid))
          .toSet()
          .toList(growable: false);
      if (accountUuids.isEmpty) {
        _closeAllSessions();
        _finishRefresh();
        return;
      }

      final dbPath = await ref.read(votingWalletDbPathProvider).call();
      final pending = await ref
          .read(votingPendingShareRoundLoaderProvider)
          .call(dbPath: dbPath, accountUuids: accountUuids);
      if (pending.isEmpty) {
        _closeAllSessions();
        _finishRefresh();
        return;
      }

      if (refreshConfig && ref.exists(votingConfigProvider)) {
        await ref.read(votingConfigProvider.notifier).refresh();
      }
      final authenticatedRoundIds = await ref
          .read(votingAuthenticatedRoundIdsLoaderProvider)
          .call();
      if (_pauseWhileLocked()) return;
      final accountUuidSet = accountUuids.toSet();
      final candidateKeys = {
        for (final round in pending)
          if (accountUuidSet.contains(round.accountUuid) &&
              !_quiescedAccountUuids.contains(round.accountUuid) &&
              authenticatedRoundIds.contains(round.roundId))
            VotingSessionKey(
              roundId: round.roundId,
              accountUuid: round.accountUuid,
            ),
      };
      _retainOnly(candidateKeys);

      final orderedKeys = candidateKeys.toList(growable: false)
        ..sort((left, right) {
          final accountOrder = left.accountUuid.compareTo(right.accountUuid);
          return accountOrder != 0
              ? accountOrder
              : left.roundId.compareTo(right.roundId);
        });
      for (final key in orderedKeys) {
        if (!_sessions.containsKey(key)) continue;
        if (_isTrackingQuiesced(key.accountUuid)) {
          _closeSession(key);
          continue;
        }
        final provider = votingSubmissionSessionProvider(key);
        try {
          final round = (await ref.read(provider.future)).round;
          if (_pauseWhileLocked()) return;
          if (!_sessions.containsKey(key)) continue;
          if (_isTrackingQuiesced(key.accountUuid)) {
            _closeSession(key);
            continue;
          }
          if (round == null || !shouldTrackPendingVotingShares(round)) {
            _closeSession(key);
            continue;
          }
          if (checkedKeys.contains(key)) continue;
          final notifier = ref.read(provider.notifier);
          notifier.resumeShareTracking();
          await notifier.submitPendingShares();
          checkedKeys.add(key);
        } catch (error, stackTrace) {
          firstError ??= error;
          _closeSession(key);
          debugPrint(
            '[zcash] Voting: background share check paused '
            'round=${key.roundId} account=${key.accountUuid} error=$error\n'
            '$stackTrace',
          );
        }
      }
    } catch (error, stackTrace) {
      firstError = error;
      debugPrint(
        '[zcash] Voting: pending share discovery paused error=$error\n'
        '$stackTrace',
      );
    }

    if (firstError != null) {
      _scheduleDiscoveryRetry();
    }
    _finishRefresh(error: firstError);
  }

  /// Stops retained tracking for one account, or every account when omitted,
  /// and waits until active passes can no longer access the voting sidecar.
  Future<void> quiesceAndDrain({String? accountUuid}) async {
    if (accountUuid == null) {
      _allTrackingQuiesced = true;
      _cancelDiscoveryRetry();
    } else {
      _quiescedAccountUuids.add(accountUuid);
    }

    while (true) {
      final keys = _sessionKeysForScope(accountUuid);
      await Future.wait(keys.map(_stopSession));
      for (final key in keys) {
        _closeSession(key);
      }

      final refresh = _refreshInFlight;
      if (refresh != null) {
        await refresh;
        continue;
      }
      if (_sessionKeysForScope(accountUuid).isEmpty) break;
    }
    _finishRefresh();
  }

  /// Ends a destructive-mutation pause and optionally rechecks durable work.
  void resumeAfterMutation({String? accountUuid, bool refresh = true}) {
    if (accountUuid == null) {
      _allTrackingQuiesced = false;
    } else {
      _quiescedAccountUuids.remove(accountUuid);
    }
    if (refresh) unawaited(this.refresh());
  }

  bool _isTrackingQuiesced(String accountUuid) {
    return _allTrackingQuiesced || _quiescedAccountUuids.contains(accountUuid);
  }

  List<VotingSessionKey> _sessionKeysForScope(String? accountUuid) {
    return [
      for (final key in _sessions.keys)
        if (accountUuid == null || key.accountUuid == accountUuid) key,
    ];
  }

  Future<void> _stopSession(VotingSessionKey key) async {
    try {
      await ref
          .read(votingSubmissionSessionProvider(key).notifier)
          .stopAndDrainShareTracking();
    } catch (error, stackTrace) {
      debugPrint(
        '[zcash] Voting: share tracking pass ended while draining '
        'round=${key.roundId} account=${key.accountUuid} error=$error\n'
        '$stackTrace',
      );
    }
  }

  bool _pauseWhileLocked() {
    if (!ref.read(appSecurityProvider).requiresUnlock) return false;
    _cancelDiscoveryRetry();
    _closeAllSessions();
    _finishRefresh();
    return true;
  }

  void _retainOnly(Set<VotingSessionKey> keys) {
    for (final key in _sessions.keys.toList(growable: false)) {
      if (!keys.contains(key)) _closeSession(key);
    }
    for (final key in keys) {
      _sessions.putIfAbsent(key, () => _listenToSession(key));
    }
  }

  ProviderSubscription<AsyncValue<VotingSessionState>> _listenToSession(
    VotingSessionKey key,
  ) {
    final provider = votingSubmissionSessionProvider(key);
    late final ProviderSubscription<AsyncValue<VotingSessionState>>
    subscription;
    subscription = ref.listen<AsyncValue<VotingSessionState>>(provider, (
      _,
      next,
    ) {
      if (!_hasTerminalShareTrackingState(next)) return;
      scheduleMicrotask(() {
        if (!ref.mounted || !identical(_sessions[key], subscription)) return;
        if (!_hasTerminalShareTrackingState(ref.read(provider))) return;
        _closeSession(key);
        _finishRefresh();
      });
    }, fireImmediately: true);
    ref.read(provider.notifier).releaseShareTrackingOwnership();
    return subscription;
  }

  bool _hasTerminalShareTrackingState(AsyncValue<VotingSessionState> session) {
    if (session is! AsyncData<VotingSessionState>) return false;
    final value = session.value;
    final round = value.round;
    if (round != null && !shouldTrackPendingVotingShares(round)) return true;
    return value.resumePlan?.unconfirmedShareDelegations.isEmpty ?? false;
  }

  void _closeSession(VotingSessionKey key) {
    _sessions.remove(key)?.close();
  }

  void _closeAllSessions() {
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
  }

  void _scheduleDiscoveryRetry() {
    if (_discoveryRetryTimer?.isActive ?? false) return;
    final configuredDelay = ref.read(
      votingPendingShareDiscoveryRetryDelayProvider,
    );
    final delay = configuredDelay.isNegative ? Duration.zero : configuredDelay;
    debugPrint(
      '[zcash] Voting: pending share discovery will retry '
      'delay=${delay.inSeconds}s',
    );
    _discoveryRetryTimer = Timer(delay, () {
      _discoveryRetryTimer = null;
      if (!ref.mounted) return;
      unawaited(refresh(refreshConfig: true));
    });
  }

  void _cancelDiscoveryRetry() {
    _discoveryRetryTimer?.cancel();
    _discoveryRetryTimer = null;
  }

  void _finishRefresh({Object? error}) {
    if (!ref.mounted) return;
    state = VotingShareTrackingCoordinatorState(
      trackedRoundCount: _sessions.length,
      lastError: error,
    );
  }
}

final votingShareTrackingCoordinatorProvider =
    NotifierProvider<
      VotingShareTrackingCoordinatorNotifier,
      VotingShareTrackingCoordinatorState
    >(VotingShareTrackingCoordinatorNotifier.new);

/// Keeps persisted share tracking alive outside the voting route.
class VotingShareTrackingCoordinatorHost extends ConsumerStatefulWidget {
  const VotingShareTrackingCoordinatorHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VotingShareTrackingCoordinatorHost> createState() =>
      _VotingShareTrackingCoordinatorHostState();
}

class _VotingShareTrackingCoordinatorHostState
    extends ConsumerState<VotingShareTrackingCoordinatorHost> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(votingShareTrackingCoordinatorProvider.notifier).refresh(),
      );
    });
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(
        ref
            .read(votingShareTrackingCoordinatorProvider.notifier)
            .refresh(refreshConfig: true),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
