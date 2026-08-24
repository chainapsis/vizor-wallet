import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/number_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_service_providers.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../services/voting/voting_models.dart';
import '../../../services/voting/resolved_voting_config_extensions.dart';
import '../voting_choice_style.dart';
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_poll_ordering.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';

const int _ballotDivisorZatoshi = 12500000;
const _pendingTallyRefreshInterval = Duration(seconds: 10);

final _roundTallyProvider = FutureProvider.autoDispose.family((
  ref,
  String roundId,
) async {
  final config = await ref.watch(votingConfigProvider.future);
  config.assertRoundAuthenticated(roundId);
  return ref
      .read(votingApiClientProvider(config.apiServers))
      .getRoundTally(roundId);
});

class VotingResultsScreen extends StatelessWidget {
  const VotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: VotingResultsView(roundId: roundId, showDesktopToolbar: true),
      ),
    );
  }
}

class VotingResultsView extends ConsumerStatefulWidget {
  const VotingResultsView({
    required this.roundId,
    required this.showDesktopToolbar,
    super.key,
  });

  final String roundId;
  final bool showDesktopToolbar;

  @override
  ConsumerState<VotingResultsView> createState() => _VotingResultsViewState();
}

class _VotingResultsViewState extends ConsumerState<VotingResultsView> {
  Timer? _pendingTallyRefreshTimer;

  @override
  void didUpdateWidget(covariant VotingResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId != widget.roundId) {
      _clearPendingTallyRefresh();
    }
  }

  @override
  void dispose() {
    _clearPendingTallyRefresh();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(votingSessionProvider(widget.roundId));
    final tally = ref.watch(_roundTallyProvider(widget.roundId));
    final accountState = kAppFormFactor == AppFormFactor.mobile
        ? ref.watch(accountProvider).value
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDesktopToolbar) const AppPaneToolbar(),
        Expanded(
          child: tally.when(
            skipLoadingOnRefresh: false,
            loading: () => const VotingPaneLoading(),
            error: (error, _) {
              final round = session.value?.round;
              if (round != null &&
                  _roundIsTallying(round) &&
                  _isTallyNotReadyError(error)) {
                return _pendingResults();
              }
              _clearPendingTallyRefresh();
              return _Message(
                "Couldn't load results: ${friendlyVotingErrorMessage(error)}",
              );
            },
            data: (result) {
              final round = session.value?.round;
              if (round == null) {
                _clearPendingTallyRefresh();
                if (session.hasError) {
                  return _Message(
                    "Couldn't load voting round details: "
                    "${friendlyVotingErrorMessage(session.error!)}",
                  );
                }
                return const VotingPaneLoading();
              }
              final proposals = proposalsFromRound(round);
              if (_isTallying(result.rawJson)) {
                return _pendingResults();
              }
              _clearPendingTallyRefresh();
              return VotingPaneScrollView(
                maxWidth: 560,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.showDesktopToolbar ? 0 : AppSpacing.sm,
                ),
                scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ResultsHeader(
                      title: _roundTitle(round),
                      snapshotHeight: round.snapshotHeight,
                      description: _roundDescription(round) ?? '',
                      forumUri: votingRoundForumUriFromJson(round.rawJson),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Results',
                      style: AppTypography.headlineSmall.copyWith(
                        color: context.colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    if (proposals.isEmpty)
                      const _Message('No proposals in this round.')
                    else
                      for (var index = 0; index < proposals.length; index++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: index == proposals.length - 1
                                ? 0
                                : AppSpacing.s,
                          ),
                          child: VotingResultCard(
                            key: ValueKey(
                              'voting-result-card-${proposals[index].id}',
                            ),
                            proposal: proposals[index],
                            tally: _proposalTally(
                              result.rawJson,
                              proposals[index].id,
                            ),
                            selectedChoice: _selectedChoiceForProposal(
                              session.value,
                              proposals[index].id,
                            ),
                            profilePictureId: _profilePictureIdForAccount(
                              accountState,
                              session.value?.accountUuid,
                            ),
                          ),
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _pendingResults() {
    _schedulePendingTallyRefresh();
    return const _Message('Results pending...');
  }

  void _schedulePendingTallyRefresh() {
    if (_pendingTallyRefreshTimer != null) return;
    _pendingTallyRefreshTimer = Timer(_pendingTallyRefreshInterval, () {
      _pendingTallyRefreshTimer = null;
      if (!mounted) return;
      ref.invalidate(_roundTallyProvider(widget.roundId));
    });
  }

  void _clearPendingTallyRefresh() {
    _pendingTallyRefreshTimer?.cancel();
    _pendingTallyRefreshTimer = null;
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final description = this.description.trim();
    final descriptionStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
      height: 20 / 14,
      letterSpacing: 0,
    );
    final titleStyle = AppTypography.headlineMedium.copyWith(
      color: colors.text.accent,
      fontFamily: 'Geist',
      fontWeight: FontWeight.w600,
      fontSize: 20,
      height: 30 / 20,
      letterSpacing: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${formatGroupedInteger(snapshotHeight)}',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          VotingExpandableText(text: description, style: descriptionStyle),
        ],
        if (forumUri != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: VotingForumLinkButton(uri: forumUri!),
          ),
        ],
      ],
    );
  }
}

class VotingResultCard extends StatelessWidget {
  const VotingResultCard({
    super.key,
    required this.proposal,
    required this.tally,
    required this.selectedChoice,
    this.profilePictureId,
  });

  final VotingProposalView proposal;
  final Map<int, num> tally;
  final int? selectedChoice;
  final String? profilePictureId;

  @override
  Widget build(BuildContext context) {
    final total = tally.values.fold<num>(0, (sum, value) => sum + value);
    final winningOption = _singleWinningOption(proposal.options, tally, total);
    final selectedLabel = _optionLabel(proposal.options, selectedChoice);
    final zipBadges = proposal.zipBadges;
    final forumUri = proposal.forumUri;

    if (kAppFormFactor == AppFormFactor.mobile) {
      return _MobileResultCard(
        proposal: proposal,
        tally: tally,
        total: total,
        selectedChoice: selectedChoice,
        profilePictureId: profilePictureId,
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: context.colors.border.subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (zipBadges.isNotEmpty || forumUri != null) ...[
            VotingProposalMetadataRow(zipBadges: zipBadges, forumUri: forumUri),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          if (proposal.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description.trim(),
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final option in proposal.options)
            _TallyRow(
              label: option.label,
              amount: tally[option.index] ?? 0,
              total: total,
              color: _optionColor(
                context,
                option.label,
                highlighted: option.index == winningOption,
              ),
              highlighted: option.index == winningOption,
            ),
          if (selectedLabel != null || total > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                if (selectedLabel != null)
                  Expanded(
                    child: Text(
                      'Voted: $selectedLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (total > 0)
                  Text(
                    'Total: ${_formatTallyZec(total)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileResultCard extends StatelessWidget {
  const _MobileResultCard({
    required this.proposal,
    required this.tally,
    required this.total,
    required this.selectedChoice,
    required this.profilePictureId,
  });

  final VotingProposalView proposal;
  final Map<int, num> tally;
  final num total;
  final int? selectedChoice;
  final String? profilePictureId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (proposal.zipBadges.isNotEmpty)
            SizedBox(
              height: 21,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  proposal.zipBadges.join('   '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                    height: 16 / 14,
                    letterSpacing: -0.06,
                  ),
                ),
              ),
            ),
          if (proposal.zipBadges.isNotEmpty)
            const SizedBox(height: AppSpacing.xs),
          Text(
            proposal.title,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
              height: 24 / 16,
              letterSpacing: -0.24,
            ),
          ),
          if (proposal.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description.trim(),
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
                height: 21 / 14,
                letterSpacing: -0.21,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (var index = 0; index < proposal.options.length; index++) ...[
            _MobileTallyRow(
              option: proposal.options[index],
              amount: tally[proposal.options[index].index] ?? 0,
              total: total,
              selected: selectedChoice == proposal.options[index].index,
              profilePictureId: profilePictureId,
            ),
            if (index != proposal.options.length - 1)
              const SizedBox(height: AppSpacing.s),
          ],
          if (total > 0) ...[
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              height: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Total',
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                      height: 16 / 14,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _formatTallyZec(total),
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.primary,
                      height: 16 / 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileTallyRow extends StatelessWidget {
  const _MobileTallyRow({
    required this.option,
    required this.amount,
    required this.total,
    required this.selected,
    required this.profilePictureId,
  });

  final VotingOptionView option;
  final num amount;
  final num total;
  final bool selected;
  final String? profilePictureId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = total <= 0
        ? 0.0
        : (amount / total).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: colors.background.base),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress,
                heightFactor: 1,
                child: ColoredBox(
                  color: colors.background.neutralSubtleOpacity,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected ? '${option.label} (your vote)' : option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w500,
                        height: 16 / 14,
                        letterSpacing: -0.06,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _formatTallyZec(amount),
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.accent,
                      fontWeight: FontWeight.w500,
                      height: 16 / 14,
                      letterSpacing: -0.06,
                    ),
                  ),
                  if (selected && profilePictureId != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    AppProfilePicture(
                      profilePictureId: profilePictureId!,
                      size: AppProfilePictureSize.medium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
    required this.highlighted,
  });

  final String label;
  final num amount;
  final num total;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: highlighted ? color : context.colors.text.accent,
                  ),
                ),
              ),
              Text(
                _formatTallyZec(amount),
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: highlighted ? color : context.colors.text.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _TallyProgressBar(value: pct, color: color),
        ],
      ),
    );
  }
}

class _TallyProgressBar extends StatelessWidget {
  const _TallyProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 6,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.colors.background.overlay),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}

bool _isTallying(Map<String, dynamic> json) {
  final status = (json['status'] ?? json['phase'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return status == '2' || status == 'tallying' || status == 'pending';
}

bool _roundIsTallying(VotingRoundDetails round) {
  return votingPollListStatus(round.status) == VotingPollListStatus.tallying ||
      _isTallying(round.rawJson);
}

bool _isTallyNotReadyError(Object error) {
  return error is VotingHttpException && error.statusCode == 404;
}

String _roundTitle(VotingRoundDetails round) {
  final title = round.title.trim();
  return title.isEmpty ? 'Voting results' : title;
}

String? _roundDescription(VotingRoundDetails round) {
  final description = _stringFromJson(round.rawJson, const [
    'description',
    'summary',
    'body',
  ]);
  final trimmed = description?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int? _selectedChoiceForProposal(VotingSessionState? state, int proposalId) {
  final display = state?.roundPlan?.completedVoteDisplay;
  if (state?.roundPlan?.completedForDisplay != true || display == null) {
    return null;
  }
  for (final choice in display.choices) {
    if (choice.proposalId == proposalId) return choice.choice;
  }
  return null;
}

Map<int, num> _proposalTally(Map<String, dynamic> json, int proposalId) {
  final tally = <int, num>{};

  void addEntry(_TallyEntry entry) {
    tally.update(
      entry.decision,
      (existing) => existing + entry.amount,
      ifAbsent: () => entry.amount,
    );
  }

  void addEntries(Map<int, num> entries) {
    for (final entry in entries.entries) {
      addEntry(_TallyEntry(entry.key, entry.value));
    }
  }

  final direct = _directTallyEntry(json);
  final directProposalId = _intFromJson(json, const [
    'proposal_id',
    'proposalId',
    'id',
  ]);
  if (direct != null &&
      (directProposalId == null || directProposalId == proposalId)) {
    addEntry(direct);
  }

  final tallies = json['tallies'] ?? json['results'] ?? json['proposals'];
  if (tallies is Map) {
    final byProposal = _objectFromValue(tallies);
    addEntries(_entriesToTally(byProposal[proposalId.toString()]));
    if (tally.isNotEmpty) return tally;
  }

  final values = tallies is List ? tallies : const [];
  for (final value in values) {
    final object = _objectFromValue(value);
    final id = _intFromJson(object, const ['proposal_id', 'proposalId', 'id']);
    if (id == proposalId) {
      final row = _directTallyEntry(object, fallbackDecision: 0);
      if (row != null) {
        addEntry(row);
        continue;
      }
      addEntries(
        _entriesToTally(
          object['entries'] ?? object['options'] ?? object['tally'],
        ),
      );
    }
  }
  if (tally.isNotEmpty) return tally;

  return _entriesToTally(json['entries'] ?? json['tally']);
}

Map<int, num> _entriesToTally(Object? value) {
  final object = _objectFromValue(value);
  if (object.isNotEmpty) {
    final direct = _directTallyEntry(object);
    if (direct != null) return {direct.decision: direct.amount};

    final entries = <int, num>{};
    for (final entry in object.entries) {
      final decision = int.tryParse(entry.key);
      if (decision == null) continue;
      entries[decision] = _num(entry.value);
    }
    return entries;
  }
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry(int.tryParse(key.toString()) ?? 0, _num(value)),
    );
  }
  if (value is List) {
    final entries = <int, num>{};
    for (var index = 0; index < value.length; index++) {
      final direct = _directTallyEntry(
        _objectFromValue(value[index]),
        fallbackDecision: index,
      );
      if (direct == null) continue;
      entries.update(
        direct.decision,
        (existing) => existing + direct.amount,
        ifAbsent: () => direct.amount,
      );
    }
    return entries;
  }
  return const {};
}

_TallyEntry? _directTallyEntry(
  Map<String, dynamic> json, {
  int? fallbackDecision,
}) {
  final decision =
      _intFromJson(json, const [
        'vote_decision',
        'voteDecision',
        'decision',
        'choice',
        'index',
        'option',
        'option_id',
        'optionId',
      ]) ??
      fallbackDecision;
  final amount = _valueFromJson(json, const [
    'total_value',
    'totalValue',
    'amount',
    'votes',
    'value',
  ]);
  if (decision == null || amount == null) return null;
  return _TallyEntry(decision, _num(amount));
}

int? _singleWinningOption(
  List<VotingOptionView> options,
  Map<int, num> tally,
  num total,
) {
  if (total <= 0) return null;

  num? maxAmount;
  final winners = <int>[];
  for (final option in options) {
    final amount = tally[option.index] ?? 0;
    if (maxAmount == null || amount > maxAmount) {
      maxAmount = amount;
      winners
        ..clear()
        ..add(option.index);
    } else if (amount == maxAmount) {
      winners.add(option.index);
    }
  }
  return maxAmount == null || maxAmount <= 0 || winners.length != 1
      ? null
      : winners.single;
}

String? _optionLabel(List<VotingOptionView> options, int? choice) {
  if (choice == null) return null;
  for (final option in options) {
    if (option.index == choice) return option.label;
  }
  return null;
}

Color _optionColor(
  BuildContext context,
  String label, {
  required bool highlighted,
}) {
  if (!highlighted) return context.colors.text.disabled;
  return votingChoicePalette(context, label).text;
}

String _formatTallyZec(num ballotUnits) {
  // Ballot tallies are multiples of 0.125 ZEC, so they are rounded to two
  // decimals (e.g. 0.125 -> 0.13). This intentionally does not route through
  // ZecAmount, which truncates fractions rather than rounding.
  final zec = ballotUnits * _ballotDivisorZatoshi / zatoshiPerZec.toInt();
  final fixed = zec.toStringAsFixed(2);
  final parts = fixed.split('.');
  final integer = int.tryParse(parts.first) ?? 0;
  return '${formatGroupedInteger(integer)}.${parts.last} ZEC';
}

String? _profilePictureIdForAccount(
  AccountState? accountState,
  String? accountUuid,
) {
  if (accountState == null || accountUuid == null) return null;
  for (final account in accountState.accounts) {
    if (account.uuid == accountUuid) return account.profilePictureId;
  }
  return null;
}

Map<String, dynamic> _objectFromValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String? _stringFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _valueFromJson(json, keys);
  return value?.toString();
}

int? _intFromJson(Map<String, dynamic> json, List<String> keys) {
  final value = _valueFromJson(json, keys);
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

Object? _valueFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) return json[key];
  }
  return null;
}

num _num(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

class _TallyEntry {
  const _TallyEntry(this.decision, this.amount);

  final int decision;
  final num amount;
}
