import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/layout/mobile/mobile_top_scroll_fade.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/voting/voting_rounds_provider.dart';
import '../../../../providers/voting/voting_state.dart';
import '../../voting_error_messages.dart';
import '../../voting_poll_list_driver.dart';
import '../../voting_poll_ordering.dart';
import '../../widgets/voting_poll_card.dart';

/// Mobile round list — the entry screen of the voting flow, pushed
/// full-screen over the tab shell from the home entry card. Pull-to-refresh
/// replaces the desktop sidebar re-tap refresh.
class MobileVotingPollsScreen extends ConsumerStatefulWidget {
  const MobileVotingPollsScreen({super.key});

  @override
  ConsumerState<MobileVotingPollsScreen> createState() =>
      _MobileVotingPollsScreenState();
}

class _MobileVotingPollsScreenState
    extends ConsumerState<MobileVotingPollsScreen>
    with VotingPollListDriver {
  @override
  void initState() {
    super.initState();
    initPollListEntryRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final rounds = ref.watch(votingRoundsProvider);
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Vote',
              onBack: _goBack,
              trailing: const Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: VotingBetaLabel(),
              ),
            ),
            Expanded(
              child: entryRefreshInFlight && !rounds.hasValue
                  ? const Center(child: CircularProgressIndicator())
                  : (pollListRefreshInFlight || entryRefreshInFlight) &&
                        rounds.hasValue
                  ? _buildRoundList(rounds.requireValue)
                  : rounds.when(
                      skipLoadingOnRefresh: false,
                      skipLoadingOnReload: false,
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => VotingMessage(
                        title: "Couldn't load voting rounds",
                        message: friendlyVotingErrorMessage(error),
                        actionLabel: 'Try again',
                        onAction: () => reloadRoundsWithFreshConfig(),
                      ),
                      data: _buildRoundList,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundList(List<VotingRoundView> items) {
    if (items.isEmpty) {
      return const VotingMessage(
        title: 'No voting rounds available',
        message: 'There are no token holder voting rounds to display yet.',
      );
    }
    final sortedItems = sortVotingRoundsForPollList(items);
    preSyncVisibleRoundTrees(sortedItems);
    return MobileTopScrollFade(
      child: RefreshIndicator.adaptive(
        onRefresh: _handlePullRefresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.s,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          itemCount: sortedItems.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.base),
          itemBuilder: (context, index) {
            final round = sortedItems[index];
            return VotingPollCard(
              round: round,
              onAction: () => _openRoundAction(round),
            );
          },
        ),
      ),
    );
  }

  Future<void> _handlePullRefresh() async {
    if (entryRefreshInFlight) return;
    setState(() {
      pollListRefreshInFlight = true;
    });
    try {
      await refreshConfigAndReloadRounds();
    } finally {
      if (mounted) {
        setState(() {
          pollListRefreshInFlight = false;
        });
      }
    }
  }

  void _openRoundAction(VotingRoundView round) {
    unawaited(
      context.push(pollRoundActionRoute(round)).whenComplete(() {
        if (!mounted) return;
        reloadRoundsWithFreshConfig();
      }),
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }
}
