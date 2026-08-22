import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../providers/voting/voting_tree_sync_provider.dart';
import '../voting_error_messages.dart';
import '../voting_poll_ordering.dart';
import '../voting_routes.dart';
import '../widgets/voting_config_settings_panel.dart';
import '../widgets/voting_pane_scroll_area.dart';
import '../widgets/voting_poll_card.dart';

const _votingBetaLabelCenterDx = 34.0;
const _votingBetaLabelTopOffset = -10.0;
const _votingHeaderTitleHeight = 33.0;

class VotingPollsScreen extends ConsumerStatefulWidget {
  const VotingPollsScreen({super.key});

  @override
  ConsumerState<VotingPollsScreen> createState() => _VotingPollsScreenState();
}

class _VotingPollsScreenState extends ConsumerState<VotingPollsScreen> {
  bool _showSettings = false;
  bool _entryRefreshInFlight = true;
  bool _pollListRefreshInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_wasPollListRecentlyRefreshed()) {
        setState(() {
          _entryRefreshInFlight = false;
        });
        _preSyncLoadedRounds();
        return;
      }
      if (_isInitialPollListLoadInFlight()) {
        _awaitInitialPollListLoad();
        return;
      }
      _reloadRoundsWithFreshConfig(entryRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(votingPollListRefreshRequestProvider, (_, _) {
      _handleExternalRefreshRequest();
    });
    final rounds = ref.watch(votingRoundsProvider);
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppPaneToolbar(backLinkMinWidth: 60),
                _VotingHeader(onSettings: _openSettings),
                Expanded(
                  child: _entryRefreshInFlight && !rounds.hasValue
                      ? const VotingPaneLoading()
                      : (_pollListRefreshInFlight || _entryRefreshInFlight) &&
                            rounds.hasValue
                      ? _buildRoundList(rounds.requireValue)
                      : rounds.when(
                          skipLoadingOnRefresh: false,
                          skipLoadingOnReload: false,
                          loading: () => const VotingPaneLoading(),
                          error: (error, _) => VotingMessage(
                            title: "Couldn't load voting rounds",
                            message: friendlyVotingErrorMessage(error),
                            actionLabel: 'Try again',
                            onAction: () => _reloadRoundsWithFreshConfig(),
                          ),
                          data: _buildRoundList,
                        ),
                ),
              ],
            ),
            if (_showSettings)
              AppPaneModalOverlay(
                onDismiss: _closeSettings,
                child: VotingConfigSettingsPanel(
                  onClose: _closeSettings,
                  onUpdated: _closeSettings,
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
    _preSyncVisibleRoundTrees(sortedItems);
    return VotingPaneListView.separated(
      maxWidth: 560,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        40,
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
    );
  }

  void _preSyncVisibleRoundTrees(Iterable<VotingRoundView> rounds) {
    for (final round in rounds) {
      if (!shouldPreSyncVotingTree(round.status)) continue;
      unawaited(
        ref.read(votingTreePreSyncProvider).preSyncRound(round.roundId),
      );
      return;
    }
  }

  void _preSyncLoadedRounds() {
    unawaited(
      ref
          .read(votingRoundsProvider.future)
          .then((rounds) {
            if (!mounted) return;
            _preSyncVisibleRoundTrees(rounds);
          })
          .catchError((Object error) {
            debugPrint(
              '[zcash] Voting: vote tree pre-sync skipped '
              'reason=rounds-load-failed error=$error',
            );
          }),
    );
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
          _preSyncVisibleRoundTrees(rounds);
        }
      } catch (_) {
        // The provider state already carries the load error for the UI.
      } finally {
        if (mounted) {
          setState(() {
            _entryRefreshInFlight = false;
          });
        }
      }
    }());
  }

  void _openRoundAction(VotingRoundView round) {
    final state = votingPollCardState(round);
    final route =
        state == VotingPollCardState.tallying ||
            state == VotingPollCardState.closed
        ? votingResultsRoute(round.roundId)
        : votingPollRoute(round.roundId);
    _pushRoundRoute(route);
  }

  void _pushRoundRoute(String route) {
    unawaited(
      context.push(route).whenComplete(() {
        if (!mounted) return;
        _reloadRoundsWithFreshConfig();
      }),
    );
  }

  void _reloadRoundsWithFreshConfig({bool entryRefresh = false}) {
    if (!entryRefresh && (_entryRefreshInFlight || _pollListRefreshInFlight)) {
      return;
    }
    if (!entryRefresh && ref.read(votingRoundsProvider).hasValue) {
      setState(() {
        _pollListRefreshInFlight = true;
      });
    }
    unawaited(
      _refreshConfigAndReloadRounds().whenComplete(() {
        if (!mounted) return;
        setState(() {
          if (entryRefresh) {
            _entryRefreshInFlight = false;
          }
          _pollListRefreshInFlight = false;
        });
      }),
    );
  }

  void _handleExternalRefreshRequest() {
    if (!mounted) return;
    _reloadRoundsWithFreshConfig();
  }

  bool _wasPollListRecentlyRefreshed() {
    return wasVotingPollListRecentlyRefreshed();
  }

  Future<void> _refreshConfigAndReloadRounds() async {
    await refreshVotingPollList(
      config: ref.read(votingConfigProvider.notifier),
      readRounds: () => ref.read(votingRoundsProvider.notifier),
      shouldReload: () => mounted,
    );
    if (!mounted) return;
    _preSyncLoadedRounds();
  }

  void _openSettings() {
    setState(() {
      _showSettings = true;
    });
  }

  void _closeSettings() {
    setState(() {
      _showSettings = false;
    });
  }
}

class _VotingHeader extends StatelessWidget {
  const _VotingHeader({required this.onSettings});

  final VoidCallback onSettings;

  // Matches the poll list track (VotingPaneListView.maxWidth) so the title and
  // the gear align with the list below.
  static const _contentMaxWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    // Redesign header: a centered "Vote" title with a filters row beneath it.
    // The settings gear sits at the trailing edge of that row (moved out of the
    // pane toolbar, which now carries only the back link). The Basic/New/Active
    // status tabs and the search affordance are deferred until the redesign
    // finalizes their semantics, so the tab slot is intentionally empty.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('voting_header_title_row'),
                height: _votingHeaderTitleHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    Text(
                      'Vote',
                      key: const ValueKey('voting_header_title'),
                      style: AppTypography.headlineLarge.copyWith(
                        color: context.colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Positioned(
                      top: _votingBetaLabelTopOffset,
                      child: Transform.translate(
                        offset: const Offset(_votingBetaLabelCenterDx, 0),
                        child: const VotingBetaLabel(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    const Spacer(),
                    AppIconHoverButton(
                      icon: AppIcons.cog,
                      tooltip: 'Voting config',
                      semanticLabel: 'Voting config settings',
                      onTap: onSettings,
                      size: 24,
                      iconSize: 16,
                      borderRadius: BorderRadius.circular(AppRadii.xSmall),
                      hoverColor: context.colors.state.hover,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

