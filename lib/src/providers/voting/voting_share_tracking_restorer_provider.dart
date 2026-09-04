import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';
import '../../rust/api/voting.dart' as rust_api;
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../account_provider.dart';
import '../app_security_provider.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_state.dart';

typedef VotingPendingShareRoundLoader =
    Future<List<rust_api.ApiPendingShareRound>> Function({
      required String dbPath,
      required List<String> accountUuids,
    });

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

@visibleForTesting
final votingPendingShareRestoreRetryDelayProvider = Provider((ref) {
  return const Duration(seconds: 15);
});

class VotingShareTrackingRestorer {
  VotingShareTrackingRestorer(this._ref);

  final Ref _ref;
  Future<void>? _restoreInFlight;
  Future<void> _pauseInFlight = Future.value();
  Timer? _retryTimer;
  bool _isPaused = false;
  int _pauseGeneration = 0;

  Future<void> restore() {
    final inFlight = _restoreInFlight;
    if (inFlight != null) return inFlight;

    _cancelRetry();
    if (_ref.read(appSecurityProvider).requiresUnlock) return Future.value();
    final registry = _ref.read(votingShareTrackingRegistryProvider);
    final releaseDiscovery = registry.beginDiscovery();
    // A request rejected by quiescence is not active work. Recording its
    // already-completed future would swallow a request made just after resume.
    if (releaseDiscovery == null) return Future.value();

    late final Future<void> restore;
    restore = _restoreTracked(registry).whenComplete(() {
      try {
        releaseDiscovery();
      } finally {
        if (identical(_restoreInFlight, restore)) _restoreInFlight = null;
      }
    });
    _restoreInFlight = restore;
    return restore;
  }

  Future<void> pause() {
    _cancelRetry();
    _pauseGeneration++;
    if (_isPaused) return _pauseInFlight;
    _isPaused = true;
    final pause = _ref
        .read(votingShareTrackingRegistryProvider)
        .quiesceAndDrain();
    return _pauseInFlight = pause.catchError((Object error, StackTrace stack) {
      debugPrint('[zcash] Voting: share tracking pause failed: $error\n$stack');
    });
  }

  Future<void> resume() async {
    final pauseGeneration = _pauseGeneration;
    if (_isPaused) {
      try {
        await _pauseInFlight;
      } finally {
        // A newer pause owns the desired state even when it reused this drain.
        if (_isPaused && pauseGeneration == _pauseGeneration) {
          _isPaused = false;
          _ref.read(votingShareTrackingRegistryProvider).resume();
        }
      }
    }
    await _restoreInFlight;
    await restore();
  }

  Future<void> _restoreTracked(VotingShareTrackingRegistry registry) async {
    var failed = false;
    try {
      final accounts = (await _ref.read(accountProvider.future)).accounts;
      final accountUuids = accounts
          .map((account) => account.uuid)
          .toList(growable: false);
      if (accountUuids.isEmpty) return;
      final dbPath = await _ref.read(votingWalletDbPathProvider).call();
      final pending = await _ref
          .read(votingPendingShareRoundLoaderProvider)
          .call(dbPath: dbPath, accountUuids: accountUuids);
      if (pending.isEmpty) return;

      final accountSet = accountUuids.toSet();
      final candidates = pending
          .where(
            (round) =>
                accountSet.contains(round.accountUuid) &&
                !registry.isQuiesced(round.accountUuid) &&
                votingSessionVoteEndTime(round.sessionJson) != null,
          )
          .toList(growable: false);
      if (candidates.isEmpty) return;

      if (_ref.exists(votingConfigProvider)) {
        await _ref.read(votingConfigProvider.notifier).refresh();
      }
      if (_ref.read(appSecurityProvider).requiresUnlock) return;
      final config = await _ref.read(votingConfigProvider.future);
      for (final round in candidates) {
        if (!config.isRoundAuthenticated(round.roundId) ||
            registry.isQuiesced(round.accountUuid)) {
          continue;
        }
        final key = VotingSessionKey(
          accountUuid: round.accountUuid,
          roundId: round.roundId,
        );
        final provider = votingSubmissionSessionProvider(key);
        // Hold the auto-disposed session through asynchronous initialization.
        final subscription = _ref.listen<AsyncValue<VotingSessionState>>(
          provider,
          (_, _) {},
          fireImmediately: true,
        );
        try {
          final session = await _ref.read(provider.future);
          if (_ref.read(appSecurityProvider).requiresUnlock) break;
          if (registry.isQuiesced(round.accountUuid)) continue;
          final liveRound = session.round;
          // The sidecar session JSON is immutable after the round is first
          // inserted, so its cached deadline may predate a server extension.
          // Session initialization has just loaded authenticated live status;
          // use that result as the recovery boundary and avoid any helper/DB
          // tracking pass when the server says the round is closed.
          if (liveRound == null || !shouldTrackPendingVotingShares(liveRound)) {
            continue;
          }
          final notifier = _ref.read(provider.notifier);
          notifier.resumeShareTracking();
          await notifier.runShareTrackingPassIfStale();
        } catch (error, stackTrace) {
          failed = true;
          debugPrint(
            '[zcash] Voting: pending share restore failed '
            'round=${round.roundId} account=${round.accountUuid} '
            'error=$error\n$stackTrace',
          );
        } finally {
          subscription.close();
        }
      }
    } catch (error, stackTrace) {
      failed = true;
      debugPrint(
        '[zcash] Voting: pending share discovery failed: $error\n$stackTrace',
      );
    }
    if (failed && !_ref.read(appSecurityProvider).requiresUnlock) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final configured = _ref.read(votingPendingShareRestoreRetryDelayProvider);
    final delay = configured.isNegative ? Duration.zero : configured;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(restore());
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

final votingShareTrackingRestorerProvider = Provider((ref) {
  final restorer = VotingShareTrackingRestorer(ref);
  final registry = ref.read(votingShareTrackingRegistryProvider);
  void requestRestore() => unawaited(restorer.restore());
  registry.addRestoreRequestListener(requestRestore);
  ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
    if (next.requiresUnlock) {
      unawaited(restorer.pause());
    } else if (previous?.requiresUnlock == true) {
      unawaited(restorer.resume());
    }
  });
  unawaited(restorer.restore());
  final lifecycleListener = AppLifecycleListener(
    onResume: () => unawaited(restorer.restore()),
  );
  ref.onDispose(() {
    registry.removeRestoreRequestListener(requestRestore);
    lifecycleListener.dispose();
    restorer._cancelRetry();
  });
  return restorer;
});
