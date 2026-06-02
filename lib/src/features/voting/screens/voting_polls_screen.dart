import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../providers/voting/voting_tree_sync_provider.dart';
import '../voting_poll_ordering.dart';
import '../voting_routes.dart';
import '../widgets/voting_config_settings_panel.dart';
import '../widgets/voting_pane_scroll_area.dart';

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
      _reloadRoundsWithFreshConfig(entryRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
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
                _VotingTopBar(onSettings: _openSettings),
                const SizedBox(height: AppSpacing.s),
                Expanded(
                  child: _entryRefreshInFlight && !rounds.hasValue
                      ? const Center(child: CircularProgressIndicator())
                      : (_pollListRefreshInFlight || _entryRefreshInFlight) &&
                            rounds.hasValue
                      ? _buildRoundList(rounds.requireValue)
                      : rounds.when(
                          skipLoadingOnRefresh: false,
                          skipLoadingOnReload: false,
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => _VotingMessage(
                            title: "Couldn't load polls",
                            message: error.toString(),
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
      return const _VotingMessage(
        title: 'No polls available',
        message: 'There are no coinholder polls to display yet.',
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
        return _PollCard(round: round, onAction: () => _openRoundAction(round));
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

  void _openRoundAction(VotingRoundView round) {
    final state = _pollCardState(round);
    final route =
        state == _PollCardState.tallying || state == _PollCardState.closed
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

class _VotingTopBar extends StatelessWidget {
  const _VotingTopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: SizedBox(
        height: AppBackLink.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: AppRouteBackLink(minWidth: 60),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _VotingTopBarIconButton(
                icon: AppIcons.cog,
                tooltip: 'Voting config',
                semanticLabel: 'Voting config settings',
                onTap: onSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VotingTopBarIconButton extends StatefulWidget {
  const _VotingTopBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onTap,
  });

  final String icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_VotingTopBarIconButton> createState() =>
      _VotingTopBarIconButtonState();
}

class _VotingTopBarIconButtonState extends State<_VotingTopBarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: ExcludeSemantics(
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: AppBackLink.height,
                height: AppBackLink.height,
                decoration: BoxDecoration(
                  color: _hovered ? colors.state.hover : null,
                  borderRadius: BorderRadius.circular(AppRadii.xSmall),
                ),
                child: Center(
                  child: AppIcon(
                    widget.icon,
                    size: 20,
                    color: colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.round, required this.onAction});

  final VotingRoundView round;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = round.title.isEmpty ? round.roundId : round.title;
    final description = _roundDescription(round.rawJson);
    final state = _pollCardState(round);
    final dateLabel = _roundDateLabel(round.rawJson, state);

    return Material(
      color: const Color(0x00000000),
      child: Ink(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: colors.border.subtle),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0A231F20),
              offset: const Offset(0, 1),
              blurRadius: 1,
              spreadRadius: -0.5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusBadge(state: state),
                const Spacer(),
                if (dateLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      dateLabel,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                        height: 20 / 14,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              description.isEmpty ? round.roundId : description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.primary,
                height: 20 / 14,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                onPressed: onAction,
                variant: _actionButtonVariant(state),
                size: AppButtonSize.medium,
                child: Text(_actionLabel(state)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final _PollCardState state;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: _statusBackground(state),
        border: Border.all(color: _statusBorder(state)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(_statusIcon(state), size: 14, color: _statusText(state)),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              color: _statusText(state),
              height: 20 / 14,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _VotingMessage extends StatelessWidget {
  const _VotingMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: onAction,
                variant: AppButtonVariant.primary,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _roundDescription(Map<String, dynamic> json) {
  for (final key in const ['description', 'body', 'summary']) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

String? _roundDateLabel(Map<String, dynamic> json, _PollCardState state) {
  final start = votingRoundStartDate(json);
  final end = votingRoundEndDate(json);
  if (end != null) {
    final label = switch (state) {
      _PollCardState.inProgress ||
      _PollCardState.active ||
      _PollCardState.voted => 'Closes',
      _PollCardState.tallying || _PollCardState.closed => 'Closed',
    };
    return '$label ${formatMonthDay(end)}';
  }
  if (start != null) return 'Starts ${formatMonthDay(start)}';
  return null;
}

String _statusLabel(_PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress => 'In progress',
    _PollCardState.active => 'Active',
    _PollCardState.voted => 'Voted',
    _PollCardState.tallying => 'Tallying',
    _PollCardState.closed => 'Closed',
  };
}

String _statusIcon(_PollCardState state) {
  return switch (state) {
    _PollCardState.voted => AppIcons.check,
    _ => AppIcons.time,
  };
}

Color _statusBackground(_PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress ||
    _PollCardState.active ||
    _PollCardState.voted => const Color(0xFFECFDF3),
    _PollCardState.tallying => const Color(0xFFFFFAEB),
    _PollCardState.closed => const Color(0xFFF4F4F0),
  };
}

Color _statusBorder(_PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress ||
    _PollCardState.active ||
    _PollCardState.voted => const Color(0xFFABEFC6),
    _PollCardState.tallying => const Color(0xFFFEDF89),
    _PollCardState.closed => const Color(0xFFEBEBE6),
  };
}

Color _statusText(_PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress ||
    _PollCardState.active ||
    _PollCardState.voted => const Color(0xFF067647),
    _PollCardState.tallying => const Color(0xFFB54708),
    _PollCardState.closed => const Color(0xFF716C5D),
  };
}

String _actionLabel(_PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress => 'Resume',
    _PollCardState.active => 'Enter poll',
    _PollCardState.voted => 'Review',
    _PollCardState.tallying || _PollCardState.closed => 'View results',
  };
}

AppButtonVariant _actionButtonVariant(_PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress ||
    _PollCardState.active => AppButtonVariant.primary,
    _PollCardState.voted ||
    _PollCardState.tallying ||
    _PollCardState.closed => AppButtonVariant.secondary,
  };
}

enum _PollCardState { inProgress, active, voted, tallying, closed }

_PollCardState _pollCardState(VotingRoundView round) {
  return switch (votingPollListStatus(round.status)) {
    VotingPollListStatus.active =>
      round.inProgress
          ? _PollCardState.inProgress
          : round.voted
          ? _PollCardState.voted
          : _PollCardState.active,
    VotingPollListStatus.tallying => _PollCardState.tallying,
    VotingPollListStatus.closed => _PollCardState.closed,
  };
}
