import 'dart:async';

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

/// Provides poll-list rows and route-controlled polling.
///
/// Polling is opt-in through [startPolling] so screens can pause network traffic
/// when the voting tab is not mounted or visible.
class VotingRoundsNotifier extends AsyncNotifier<List<VotingRoundView>> {
  static const defaultPollInterval = Duration(seconds: 10);

  Timer? _pollTimer;
  bool _refreshInFlight = false;

  @override
  Future<List<VotingRoundView>> build() async {
    ref.onDispose(stopPolling);
    ref.watch(votingActiveAccountUuidProvider);
    return _load();
  }

  void startPolling({Duration interval = defaultPollInterval}) {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(interval, (_) => refresh());
    unawaited(refresh());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh() async {
    if (_refreshInFlight || state.isLoading) return;
    _refreshInFlight = true;
    final previous = state.value;
    if (previous == null) {
      state = const AsyncLoading<List<VotingRoundView>>();
    }
    try {
      state = AsyncData(await _load());
    } catch (error, stackTrace) {
      if (previous == null) {
        state = AsyncError(error, stackTrace);
      } else {
        debugPrint(
          '[zcash] Voting: keeping previous poll list after refresh failed: '
          '$error',
        );
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<List<VotingRoundView>> _load() async {
    final config = await ref.read(votingConfigProvider.future);
    final api = ref.read(votingApiClientProvider(config.apiBaseUrl));
    final endorser = ref.read(votingEndorserClientProvider(config.apiBaseUrl));

    final rounds = await api.listRounds();
    final authenticatedRoundIds = config.authenticatedRoundIds.toSet();
    final filteredRounds = rounds
        .where((round) => authenticatedRoundIds.contains(round.roundId))
        .toList(growable: false);
    if (filteredRounds.length != rounds.length) {
      debugPrint(
        '[zcash] Voting: filtered unauthenticated rounds '
        'shown=${filteredRounds.length} total=${rounds.length}',
      );
    }
    final endorsedIds = await endorser.getEndorsedSet();
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
