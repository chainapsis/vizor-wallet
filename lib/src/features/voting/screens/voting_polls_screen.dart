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
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_error_messages.dart';
import '../voting_poll_list_driver.dart';
import '../voting_poll_ordering.dart';
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

class _VotingPollsScreenState extends ConsumerState<VotingPollsScreen>
    with VotingPollListDriver {
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    initPollListEntryRefresh();
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
                  child: entryRefreshInFlight && !rounds.hasValue
                      ? const VotingPaneLoading()
                      : (pollListRefreshInFlight || entryRefreshInFlight) &&
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
                            onAction: () => reloadRoundsWithFreshConfig(),
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
    preSyncVisibleRoundTrees(sortedItems);
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

  void _openRoundAction(VotingRoundView round) {
    unawaited(
      context.push(pollRoundActionRoute(round)).whenComplete(() {
        if (!mounted) return;
        reloadRoundsWithFreshConfig();
      }),
    );
  }

  void _handleExternalRefreshRequest() {
    if (!mounted) return;
    reloadRoundsWithFreshConfig();
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
