import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/voting/voting_config_provider.dart';
import '../../providers/voting/voting_rounds_provider.dart';
import '../../providers/voting/voting_state.dart';
import '../../providers/voting/voting_tree_sync_provider.dart';
import 'voting_routes.dart';
import 'widgets/voting_poll_card.dart';

/// Shared refresh/pre-sync orchestration behind the poll-list screens.
///
/// Owns the entry-refresh handshake (fresh config + rounds reload on first
/// open, unless another surface just refreshed or the initial load is
/// already in flight), the in-place refresh that keeps stale rows rendered,
/// and the vote-tree pre-sync kick for the first active round. The mixing
/// screen calls [initPollListEntryRefresh] from `initState` and renders from
/// [entryRefreshInFlight] / [pollListRefreshInFlight] plus
/// `votingRoundsProvider`.
mixin VotingPollListDriver<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool entryRefreshInFlight = true;
  bool pollListRefreshInFlight = false;

  void initPollListEntryRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (wasVotingPollListRecentlyRefreshed()) {
        setState(() {
          entryRefreshInFlight = false;
        });
        preSyncLoadedRounds();
        return;
      }
      if (_isInitialPollListLoadInFlight()) {
        _awaitInitialPollListLoad();
        return;
      }
      reloadRoundsWithFreshConfig(entryRefresh: true);
    });
  }

  bool _isInitialPollListLoadInFlight() {
    final rounds = ref.read(votingRoundsProvider);
    if (!rounds.isLoading || rounds.hasValue) return false;
    if (!ref.exists(votingConfigProvider)) return false;
    final config = ref.read(votingConfigProvider);
    return config.isLoading && !config.hasValue;
  }

  void _awaitInitialPollListLoad() {
    unawaited(() async {
      try {
        final rounds = await ref.read(votingRoundsProvider.future);
        markVotingPollListRecentlyRefreshed();
        if (mounted) {
          preSyncVisibleRoundTrees(rounds);
        }
      } catch (_) {
        // The provider state already carries the load error for the UI.
      } finally {
        if (mounted) {
          setState(() {
            entryRefreshInFlight = false;
          });
        }
      }
    }());
  }

  void reloadRoundsWithFreshConfig({bool entryRefresh = false}) {
    if (!entryRefresh && (entryRefreshInFlight || pollListRefreshInFlight)) {
      return;
    }
    if (!entryRefresh && ref.read(votingRoundsProvider).hasValue) {
      setState(() {
        pollListRefreshInFlight = true;
      });
    }
    unawaited(
      refreshConfigAndReloadRounds().whenComplete(() {
        if (!mounted) return;
        setState(() {
          if (entryRefresh) {
            entryRefreshInFlight = false;
          }
          pollListRefreshInFlight = false;
        });
      }),
    );
  }

  Future<void> refreshConfigAndReloadRounds() async {
    await refreshVotingPollList(
      config: ref.read(votingConfigProvider.notifier),
      readRounds: () => ref.read(votingRoundsProvider.notifier),
      shouldReload: () => mounted,
    );
    if (!mounted) return;
    preSyncLoadedRounds();
  }

  void preSyncVisibleRoundTrees(Iterable<VotingRoundView> rounds) {
    for (final round in rounds) {
      if (!shouldPreSyncVotingTree(round.status)) continue;
      unawaited(
        ref.read(votingTreePreSyncProvider).preSyncRound(round.roundId),
      );
      return;
    }
  }

  void preSyncLoadedRounds() {
    unawaited(
      ref
          .read(votingRoundsProvider.future)
          .then((rounds) {
            if (!mounted) return;
            preSyncVisibleRoundTrees(rounds);
          })
          .catchError((Object error) {
            debugPrint(
              '[zcash] Voting: vote tree pre-sync skipped '
              'reason=rounds-load-failed error=$error',
            );
          }),
    );
  }

  /// Tallying and closed rounds open results directly; anything else opens
  /// the proposal detail.
  String pollRoundActionRoute(VotingRoundView round) {
    final state = votingPollCardState(round);
    return state == VotingPollCardState.tallying ||
            state == VotingPollCardState.closed
        ? votingResultsRoute(round.roundId)
        : votingPollRoute(round.roundId);
  }
}
