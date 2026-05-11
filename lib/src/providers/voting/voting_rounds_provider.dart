import 'dart:async';

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
    state = const AsyncLoading<List<VotingRoundView>>();
    try {
      state = await AsyncValue.guard(_load);
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
    return [
      for (final round in rounds)
        VotingRoundView.fromSummary(
          round,
          endorsed: endorsedIds.contains(round.roundId),
        ),
    ];
  }
}

final votingRoundsProvider =
    AsyncNotifierProvider<VotingRoundsNotifier, List<VotingRoundView>>(
      VotingRoundsNotifier.new,
    );
