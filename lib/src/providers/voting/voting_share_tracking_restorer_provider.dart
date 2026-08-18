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

  Future<void> restore() {
    final inFlight = _restoreInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> restore;
    restore = _restoreOnce().whenComplete(() {
      if (identical(_restoreInFlight, restore)) _restoreInFlight = null;
    });
    _restoreInFlight = restore;
    return restore;
  }

  Future<void> pause() {
    _cancelRetry();
    return _pauseInFlight = _ref
        .read(votingShareTrackingRegistryProvider)
        .quiesceAndDrain();
  }

  Future<void> resume() async {
    await _pauseInFlight;
    _ref.read(votingShareTrackingRegistryProvider).resume();
    await _restoreInFlight;
    await restore();
  }

  Future<void> _restoreOnce() async {
    _cancelRetry();
    if (_ref.read(appSecurityProvider).requiresUnlock) return;
    var failed = false;
    try {
      final registry = _ref.read(votingShareTrackingRegistryProvider);
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
      final now = DateTime.now().toUtc();
      final candidates = pending
          .where((round) {
            final voteEnd = votingSessionVoteEndTime(round.sessionJson);
            return accountSet.contains(round.accountUuid) &&
                !registry.isQuiesced(round.accountUuid) &&
                voteEnd != null &&
                now.isBefore(voteEnd);
          })
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
        try {
          await _ref.read(provider.future);
          if (_ref.read(appSecurityProvider).requiresUnlock) break;
          if (registry.isQuiesced(round.accountUuid)) continue;
          final notifier = _ref.read(provider.notifier);
          notifier.resumeShareTracking();
          await notifier.submitPendingShares();
        } catch (error, stackTrace) {
          failed = true;
          debugPrint(
            '[zcash] Voting: pending share restore failed '
            'round=${round.roundId} account=${round.accountUuid} '
            'error=$error\n$stackTrace',
          );
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
    lifecycleListener.dispose();
    restorer._cancelRetry();
  });
  return restorer;
});
