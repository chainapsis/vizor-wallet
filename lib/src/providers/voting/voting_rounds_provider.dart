import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return _load();
  }

  void startPolling({Duration interval = defaultPollInterval}) {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(interval, (_) => refresh());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh() async {
    if (_refreshInFlight) return;
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
    final endorsedIds = await endorser.getEndorsedSet();
    final votedIds = await _completedVoteRoundIds(
      rounds.map((round) => round.roundId),
    );
    return [
      for (final round in rounds)
        VotingRoundView.fromSummary(
          round,
          endorsed: endorsedIds.contains(round.roundId),
          voted: votedIds.contains(round.roundId),
        ),
    ];
  }

  Future<Set<String>> _completedVoteRoundIds(Iterable<String> roundIds) async {
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
      debugPrint('[zcash] Voting: skipped voted-state lookup: $error');
      return const {};
    }
    final recovery = ref.read(votingRecoveryServiceProvider);
    final votedIds = <String>{};
    for (final roundId in roundIds) {
      try {
        final plan = await recovery.loadResumePlan(
          dbPath: dbPath,
          walletId: accountUuid,
          roundId: roundId,
        );
        if (plan.hasCompletedVoteForDisplay) {
          votedIds.add(roundId);
        }
      } catch (error) {
        debugPrint(
          '[zcash] Voting: skipped voted-state lookup for round $roundId: '
          '$error',
        );
      }
    }
    return votedIds;
  }
}

final votingRoundsProvider =
    AsyncNotifierProvider<VotingRoundsNotifier, List<VotingRoundView>>(
      VotingRoundsNotifier.new,
    );
