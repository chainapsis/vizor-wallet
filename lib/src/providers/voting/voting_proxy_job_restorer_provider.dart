import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/proxy_delegation_feature_config.dart';
import '../../features/voting/proxy/proxy_delegator_client.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/proxy_delegator.dart' as rust_delegator;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../account_provider.dart';
import '../app_security_provider.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_state.dart';
import 'voting_submission_job_provider.dart';

/// Lists the rounds whose committed proxy allocation still owes work, or
/// whose kept share's recorded answers are not all cast, for the accounts
/// given; tests replace it.
typedef VotingPendingProxyRoundLoader =
    Future<List<rust_delegator.ApiPendingProxyRound>> Function({
      required String dbPath,
      required List<String> accountUuids,
    });

/// zcash_voting's list of rounds with unfinished proxy work.
@visibleForTesting
final votingPendingProxyRoundLoaderProvider =
    Provider<VotingPendingProxyRoundLoader>(
      (ref) =>
          ({required dbPath, required accountUuids}) =>
              rust_delegator.listPendingProxyRounds(
                dbPath: dbPath,
                accountUuids: accountUuids,
              ),
    );

/// The wallet's account ids; tests replace it.
@visibleForTesting
final votingProxyJobRestoreAccountsProvider =
    Provider<Future<List<String>> Function()>(
      (ref) =>
          () async => [
            for (final account in (await ref.read(
              accountProvider.future,
            )).accounts)
              account.uuid,
          ],
    );

/// Whether a round is still open: authenticated by the voting config,
/// active on the vote server and before its vote end. Tests replace it.
@visibleForTesting
final votingProxyRoundOpenProvider = Provider<Future<bool> Function(String)>(
  (ref) => (roundId) async {
    final config = await ref.read(votingConfigProvider.future);
    if (!config.isRoundAuthenticated(roundId)) return false;
    final round = VotingRoundDetails.fromStatus(
      await ref
          .read(votingApiClientProvider(config.apiServers))
          .getRoundStatus(roundId),
    );
    final voteEnd = round.voteEndTime;
    return voteEnd != null &&
        DateTime.now().isBefore(voteEnd) &&
        proxyRoundPhaseForStatus(round.status) ==
            rust_delegator.ApiProxyRoundPhase.active;
  },
);

/// The wait before a restore that failed is tried again; tests shorten it.
@visibleForTesting
final votingProxyJobRestoreRetryDelayProvider = Provider(
  (ref) => const Duration(seconds: 15),
);

/// Resumes proxy delegation jobs after the app starts or comes back
/// (approved review item 10.7).
///
/// A proxy job runs in memory, so after a restart it would resume only
/// when its progress screen opened or the user voted, yet a DC's shares must reach the
/// helpers before the round closes. On start, on resume and on unlock this
/// asks which rounds' committed allocations still owe work, counting kept
/// answers not yet cast after a finished handoff
/// (`listPendingProxyRounds`), and, for each round still open, starts the account's proxy job through
/// [VotingSubmissionJobsNotifier.startProxy], which keeps the vote job's
/// precedence: a job already running, of either kind, keeps the round. A
/// round whose plan still owes the casts of answers recorded with the
/// delegation ([roundPlanOwesBallotCasts]) gets the vote job instead, which
/// sends the batches first and casts once they land. The job's round driver
/// binds the round hotkey from secure storage, so nothing is restored while
/// the wallet is locked. With no unfinished allocation it makes no network
/// request.
class VotingProxyJobRestorer {
  /// Creates the restorer.
  VotingProxyJobRestorer(this._ref);

  final Ref _ref;
  Future<void>? _restoreInFlight;
  Timer? _retryTimer;

  /// A restore the quiesced registry refused, run again on its next resume.
  bool _awaitingResume = false;

  /// Restores every unfinished proxy job; joins a restore in flight. While
  /// the registry is quiesced, as while it drains between lock and unlock,
  /// the restore waits for its resume instead.
  Future<void> restore() {
    final inFlight = _restoreInFlight;
    if (inFlight != null) return inFlight;
    _cancelRetry();
    if (!_ref.read(proxyDelegationFeatureEnabledProvider)) {
      return Future.value();
    }
    if (_ref.read(appSecurityProvider).requiresUnlock) return Future.value();
    final registry = _ref.read(votingShareTrackingRegistryProvider);
    final release = registry.beginDiscovery();
    _awaitingResume = release == null;
    if (release == null) return Future.value();
    late final Future<void> restore;
    restore = _restore(registry).whenComplete(() {
      try {
        release();
      } finally {
        if (identical(_restoreInFlight, restore)) _restoreInFlight = null;
      }
    });
    return _restoreInFlight = restore;
  }

  /// One restore pass; a failure schedules another.
  Future<void> _restore(VotingShareTrackingRegistry registry) async {
    var failed = false;
    try {
      final accounts = await _ref.read(votingProxyJobRestoreAccountsProvider)();
      if (accounts.isEmpty) return;
      final dbPath = await _ref.read(votingWalletDbPathProvider)();
      final pending = await _ref.read(votingPendingProxyRoundLoaderProvider)(
        dbPath: dbPath,
        accountUuids: accounts,
      );
      final rounds = {
        for (final round in pending)
          VotingSessionKey(
            roundId: round.roundId,
            accountUuid: round.accountUuid,
          ),
      };
      for (final round in rounds) {
        if (_ref.read(appSecurityProvider).requiresUnlock) break;
        if (!accounts.contains(round.accountUuid) ||
            registry.isQuiesced(round.accountUuid)) {
          continue;
        }
        try {
          if (!await _ref.read(votingProxyRoundOpenProvider)(round.roundId)) {
            continue;
          }
          if (_ref.read(appSecurityProvider).requiresUnlock) break;
          final jobs = _ref.read(votingSubmissionJobsProvider.notifier);
          // Held until the job retains the session, so it loads once.
          final session = _ref.listen(
            votingSubmissionSessionProvider(round),
            (_, _) {},
          );
          try {
            rust_wire.RoundPlanView? plan;
            try {
              plan = (await _ref.read(
                votingSubmissionSessionProvider(round).future,
              )).roundPlan;
            } catch (error) {
              // The proxy job reports a session that cannot load.
              debugPrint(
                '[zcash] Voting: restored round plan unavailable '
                'round=${round.roundId} error=${error.runtimeType}',
              );
            }
            if (roundPlanOwesBallotCasts(plan)) {
              await jobs.start(round.roundId, accountUuid: round.accountUuid);
            } else {
              await jobs.startProxy(
                round.roundId,
                accountUuid: round.accountUuid,
              );
            }
          } finally {
            session.close();
          }
        } catch (error) {
          failed = true;
          debugPrint(
            '[zcash] Voting: proxy job restore failed '
            'round=${round.roundId} error=${error.runtimeType}',
          );
        }
      }
    } catch (error) {
      failed = true;
      debugPrint(
        '[zcash] Voting: proxy job discovery failed: ${error.runtimeType}',
      );
    }
    if (failed && !_ref.read(appSecurityProvider).requiresUnlock) {
      _scheduleRetry();
    }
  }

  /// Tries again after the retry delay.
  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final delay = _ref.read(votingProxyJobRestoreRetryDelayProvider);
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _retryTimer = null;
      unawaited(restore());
    });
  }

  /// Drops a scheduled retry.
  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Runs the restore the quiesced registry refused, if any.
  void _restoreAfterResume() {
    if (_awaitingResume) unawaited(restore());
  }
}

/// The proxy job restorer, which runs once built: the app builds it only
/// while `VIZOR_PROXY_DELEGATION_ENABLED` is on. It restores on start, when
/// the app resumes, when the wallet unlocks and when the share tracking
/// registry asks for a restore.
final votingProxyJobRestorerProvider = Provider((ref) {
  final restorer = VotingProxyJobRestorer(ref);
  final registry = ref.read(votingShareTrackingRegistryProvider);
  void requestRestore() => unawaited(restorer.restore());
  registry
    ..addRestoreRequestListener(requestRestore)
    ..addResumeListener(restorer._restoreAfterResume);
  ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
    if (previous?.requiresUnlock == true && !next.requiresUnlock) {
      unawaited(restorer.restore());
    }
  });
  unawaited(restorer.restore());
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(restorer.restore()),
  );
  ref.onDispose(() {
    registry
      ..removeRestoreRequestListener(requestRestore)
      ..removeResumeListener(restorer._restoreAfterResume);
    lifecycle.dispose();
    restorer._cancelRetry();
  });
  return restorer;
});
