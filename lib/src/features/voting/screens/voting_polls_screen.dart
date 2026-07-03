import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../providers/voting/voting_tree_sync_provider.dart';
import '../voting_error_messages.dart';
import '../voting_poll_ordering.dart';
import '../voting_flow_models.dart';
import '../voting_routes.dart';
import '../widgets/voting_config_settings_panel.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';
import '../../../../l10n/app_localizations.dart';

const _votingBetaLabelAsset = 'assets/illustrations/voting_beta_label.png';
const _votingBetaLabelWidth = 42.0;
const _votingBetaLabelHeight = 24.0;
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
                          error: (error, _) => _VotingMessage(
                            title: AppLocalizations.of(context).votingRoundsLoadFailed,
                            message: friendlyVotingErrorMessage(error, AppLocalizations.of(context)),
                            actionLabel: AppLocalizations.of(context).votingTryAgain,
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
      return _VotingMessage(
        title: AppLocalizations.of(context).votingNoRounds,
        message: AppLocalizations.of(context).votingNoRoundsBody,
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
                      AppLocalizations.of(context).votingVoteTitle,
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
                        child: const _VotingBetaLabel(),
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
                      tooltip: AppLocalizations.of(context).votingConfigTooltip,
                      semanticLabel: AppLocalizations.of(context).votingConfigSemantics,
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

class _VotingBetaLabel extends StatelessWidget {
  const _VotingBetaLabel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('voting_header_beta_label'),
      width: _votingBetaLabelWidth,
      height: _votingBetaLabelHeight,
      child: Image(
        image: const AssetImage(_votingBetaLabelAsset),
        fit: BoxFit.contain,
        semanticLabel: AppLocalizations.of(context).votingBeta,
      ),
    );
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
    final forumUri = votingRoundForumUriFromJson(round.rawJson);
    final state = _pollCardState(round);
    final dateLabel = _roundDateLabel(
      AppLocalizations.of(context),
      round.rawJson,
      state,
    );

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
            if (forumUri != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: VotingForumLinkButton(uri: forumUri),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                onPressed: onAction,
                variant: _actionButtonVariant(state),
                size: AppButtonSize.medium,
                child: Text(_actionLabel(AppLocalizations.of(context), state)),
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
    final label = _statusLabel(AppLocalizations.of(context), state);
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

String? _roundDateLabel(
  AppLocalizations l10n,
  Map<String, dynamic> json,
  _PollCardState state,
) {
  final start = votingRoundStartDate(json);
  final end = votingRoundEndDate(json);
  if (end != null) {
    final label = switch (state) {
      _PollCardState.inProgress ||
      _PollCardState.active ||
      _PollCardState.voted => l10n.votingCloses,
      _PollCardState.tallying || _PollCardState.closed => l10n.votingClosed,
    };
    return l10n.votingClosesOn(
      label,
      formatMonthDay(end, locale: l10n.localeName),
    );
  }
  if (start != null) {
    return l10n.votingStartsOn(formatMonthDay(start, locale: l10n.localeName));
  }
  return null;
}

String _statusLabel(AppLocalizations l10n, _PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress => l10n.votingStateInProgress,
    _PollCardState.active => l10n.votingStateActive,
    _PollCardState.voted => l10n.votingStateVoted,
    _PollCardState.tallying => l10n.votingStateTallying,
    _PollCardState.closed => l10n.votingClosed,
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

String _actionLabel(AppLocalizations l10n, _PollCardState state) {
  return switch (state) {
    _PollCardState.inProgress => l10n.votingResume,
    _PollCardState.active => l10n.votingStartVoting,
    _PollCardState.voted => l10n.votingReview,
    _PollCardState.tallying || _PollCardState.closed => l10n.votingViewResults,
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
