import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_models.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';

/// Provides poll-list rows with explicit, route-driven reloads.
class VotingRoundsNotifier extends AsyncNotifier<List<VotingRoundView>> {
  static const _roundsRetryDelays = <Duration>[
    Duration(milliseconds: 300),
    Duration(seconds: 1),
  ];

  Future<void>? _reloadFuture;
  bool _reloadQueued = false;

  @override
  Future<List<VotingRoundView>> build() async {
    ref.watch(votingActiveAccountUuidProvider);
    return _load();
  }

  Future<void> reload() async {
    final inFlight = _reloadFuture;
    if (inFlight != null) {
      _reloadQueued = true;
      return inFlight;
    }

    final completer = Completer<void>();
    _reloadFuture = completer.future;
    try {
      do {
        _reloadQueued = false;
        state = const AsyncLoading<List<VotingRoundView>>();
        state = await AsyncValue.guard(
          () => _withRoundsRetry(_load),
        );
      } while (_reloadQueued);
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _reloadFuture = null;
    }
  }

  Future<List<VotingRoundView>> _load() async {
    final config = await ref.read(votingConfigProvider.future);
    final api = ref.read(votingApiClientProvider(config.apiBaseUrl));
    final endorser = ref.read(votingEndorserClientProvider(config.apiBaseUrl));

    final rounds = await api.listRounds();
    final endorsedIds = await endorser.getEndorsedSet();
    final authenticatedRoundIds = config.authenticatedRounds
        .map((round) => round.roundId)
        .toSet();
    final filteredRounds = rounds
        .where((round) => authenticatedRoundIds.contains(round.roundId))
        .toList(growable: false);
    if (filteredRounds.length != rounds.length) {
      debugPrint(
        '[zcash] Voting: filtered rounds '
        '(unauthenticated) '
        'shown=${filteredRounds.length} total=${rounds.length}',
      );
    }
    final recoveryStates = await _roundListRecoveryStates(filteredRounds, api: api);
    return [
      for (final round in filteredRounds)
        VotingRoundView.fromSummary(
          round,
          endorsed: endorsedIds.contains(round.roundId),
          voted: recoveryStates[round.roundId]?.voted ?? false,
          inProgress: recoveryStates[round.roundId]?.inProgress ?? false,
        ),
    ];
  }

  Future<Map<String, _RoundListRecoveryState>> _roundListRecoveryStates(
    Iterable<VotingRoundSummary> rounds, {
    required VotingApiClient api,
  }) async {
    final String accountUuid;
    final String dbPath;
    try {
      final activeAccountUuid = await ref
          .read(votingActiveAccountUuidProvider)
          .call();
      if (activeAccountUuid == null) return const {};
      accountUuid = activeAccountUuid;
      dbPath = await ref.read(votingWalletDbPathProvider).call();
    } catch (error) {
      debugPrint('[zcash] Voting: skipped poll-state lookup: $error');
      return const {};
    }
    final states = <String, _RoundListRecoveryState>{};
    for (final round in rounds) {
      try {
        final recoveryState = await _roundListRecoveryState(
          api: api,
          dbPath: dbPath,
          accountUuid: accountUuid,
          round: round,
        );
        if (recoveryState.voted || recoveryState.inProgress) {
          states[round.roundId] = recoveryState;
        }
      } catch (error) {
        debugPrint(
          '[zcash] Voting: skipped poll-state lookup for round '
          '${round.roundId}: '
          '$error',
        );
      }
    }
    return states;
  }

  Future<_RoundListRecoveryState> _roundListRecoveryState({
    required VotingApiClient api,
    required VotingRoundSummary round,
    required String dbPath,
    required String accountUuid,
  }) async {
    final recovery = ref.read(votingRecoveryServiceProvider);
    final proposalIds = await _proposalIdsForRound(api, round);
    rust_voting.RoundPlanView? roundPlan;
    if (proposalIds.isNotEmpty) {
      try {
        roundPlan = await recovery.loadRoundPlan(
          dbPath: dbPath,
          accountUuid: accountUuid,
          roundId: round.roundId,
          proposalIds: proposalIds,
        );
      } catch (error) {
        debugPrint(
          '[zcash] Voting: skipped in-progress lookup for round '
          '${round.roundId}: $error',
        );
      }
    }
    if (hasBlockingRoundRecoveryWork(roundPlan)) {
      return const _RoundListRecoveryState(voted: false, inProgress: true);
    }
    if (hasCompletedVoteForDisplay(roundPlan)) {
      return const _RoundListRecoveryState(voted: true, inProgress: false);
    }

    return _RoundListRecoveryState(
      voted: false,
      inProgress: roundPlan?.pendingRecovery ?? false,
    );
  }

  List<int> _proposalIdsFromRoundJson(Map<String, dynamic> json) {
    try {
      return proposalsFromJson(json).map((proposal) => proposal.id).toList();
    } catch (error) {
      debugPrint(
        '[zcash] Voting: skipped proposal-id lookup for poll list row: $error',
      );
      return const [];
    }
  }

  Future<List<int>> _proposalIdsForRound(
    VotingApiClient api,
    VotingRoundSummary round,
  ) async {
    final summaryProposalIds = _proposalIdsFromRoundJson(round.rawJson);
    if (summaryProposalIds.isNotEmpty) return summaryProposalIds;

    try {
      final status = await api.getRoundStatus(round.roundId);
      return _proposalIdsFromRoundJson(status.rawJson);
    } catch (error) {
      debugPrint(
        '[zcash] Voting: skipped round detail lookup for poll-state lookup '
        'for round ${round.roundId}: $error',
      );
      return const [];
    }
  }

  Future<T> _withRoundsRetry<T>(Future<T> Function() operation) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _roundsRetryDelays.length; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt == _roundsRetryDelays.length ||
            !_isRoundsRetryable(error)) {
          rethrow;
        }
        await Future<void>.delayed(_roundsRetryDelays[attempt]);
      }
    }
    throw StateError('round reload retry exited unexpectedly: $lastError');
  }

  static bool _isRoundsRetryable(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return true;
    }
    if (error is VotingHttpException) {
      return error.statusCode == 502 || error.statusCode == 503;
    }
    return false;
  }
}

final votingRoundsProvider =
    AsyncNotifierProvider<VotingRoundsNotifier, List<VotingRoundView>>(
      VotingRoundsNotifier.new,
    );

class _RoundListRecoveryState {
  const _RoundListRecoveryState({
    required this.voted,
    required this.inProgress,
  });

  final bool voted;
  final bool inProgress;
}
