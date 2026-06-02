import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/number_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_service_providers.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../../services/voting/voting_models.dart';
import '../../../services/voting/resolved_voting_config_extensions.dart';
import '../voting_choice_style.dart';
import '../voting_flow_models.dart';
import '../voting_poll_ordering.dart';
import '../widgets/voting_pane_scroll_area.dart';

const int _ballotDivisorZatoshi = 12500000;
const _pendingTallyRefreshInterval = Duration(seconds: 10);

final _roundTallyProvider = FutureProvider.autoDispose.family((
  ref,
  String roundId,
) async {
  final config = await ref.watch(votingConfigProvider.future);
  _assertAuthenticatedRoundId(config: config, requestedRoundId: roundId);
  return ref
      .read(votingApiClientProvider(config.apiBaseUrl))
      .getRoundTally(roundId);
});

class VotingResultsScreen extends ConsumerStatefulWidget {
  const VotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingResultsScreen> createState() =>
      _VotingResultsScreenState();
}

class _VotingResultsScreenState extends ConsumerState<VotingResultsScreen> {
  Timer? _pendingTallyRefreshTimer;

  @override
  void didUpdateWidget(covariant VotingResultsScreen oldWidget) {
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

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppRouteBackLink(),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(
              child: tally.when(
                skipLoadingOnRefresh: false,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) {
                  final round = session.value?.round;
                  if (round != null &&
                      _roundIsTallying(round) &&
                      _isTallyNotReadyError(error)) {
                    return _pendingResults();
                  }
                  _clearPendingTallyRefresh();
                  return _Message("Couldn't load results: $error");
                },
                data: (result) {
                  final round = session.value?.round;
                  if (round == null) {
                    _clearPendingTallyRefresh();
                    if (session.hasError) {
                      return _Message(
                        "Couldn't load poll details: ${session.error}",
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  final proposals = proposalsFromRound(round);
                  if (_isTallying(result.rawJson)) {
                    return _pendingResults();
                  }
                  _clearPendingTallyRefresh();
                  return VotingPaneScrollView(
                    maxWidth: 720,
                    scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ResultsHeader(
                          title: _roundTitle(round),
                          snapshotHeight: round.snapshotHeight,
                          description: _roundDescription(round) ?? '',
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
                              child: _ResultCard(
                                proposal: proposals[index],
                                tally: _proposalTally(
                                  result.rawJson,
                                  proposals[index].id,
                                ),
                                selectedChoice: _selectedChoiceForProposal(
                                  session.value,
                                  proposals[index].id,
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
        ),
      ),
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

class _ResultsHeader extends StatefulWidget {
  const _ResultsHeader({
    required this.title,
    required this.snapshotHeight,
    required this.description,
  });

  final String title;
  final int snapshotHeight;
  final String description;

  @override
  State<_ResultsHeader> createState() => _ResultsHeaderState();
}

class _ResultsHeaderState extends State<_ResultsHeader> {
  bool _descriptionExpanded = false;

  @override
  void didUpdateWidget(covariant _ResultsHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.description != widget.description) {
      _descriptionExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final description = widget.description.trim();
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
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${formatGroupedInteger(widget.snapshotHeight)}',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              final canExpand = _textExceedsSingleLine(
                context: context,
                text: description,
                style: descriptionStyle,
                maxWidth: constraints.maxWidth,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    description,
                    maxLines: _descriptionExpanded || !canExpand ? null : 1,
                    overflow: _descriptionExpanded || !canExpand
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: descriptionStyle,
                  ),
                  if (canExpand)
                    Align(
                      alignment: Alignment.centerRight,
                      child: _ViewMoreButton(
                        expanded: _descriptionExpanded,
                        onPressed: () {
                          setState(() {
                            _descriptionExpanded = !_descriptionExpanded;
                          });
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.proposal,
    required this.tally,
    required this.selectedChoice,
  });

  final VotingProposalView proposal;
  final Map<int, num> tally;
  final int? selectedChoice;

  @override
  Widget build(BuildContext context) {
    final total = tally.values.fold<num>(0, (sum, value) => sum + value);
    final winningOption = _singleWinningOption(proposal.options, tally, total);
    final selectedLabel = _optionLabel(proposal.options, selectedChoice);

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
            Container(height: 1, color: context.colors.border.subtle),
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

class _ViewMoreButton extends StatelessWidget {
  const _ViewMoreButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'View less' : 'View more',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
                height: 20 / 14,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Transform.rotate(
              angle: expanded ? -1.5708 : 1.5708,
              child: AppIcon(
                AppIcons.chevronForward,
                size: 16,
                color: colors.icon.accent,
              ),
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

void _assertAuthenticatedRoundId({
  required rust_config.ResolvedVotingConfig config,
  required String requestedRoundId,
}) {
  if (config.isRoundAuthenticated(requestedRoundId)) {
    return;
  }
  final reason = config.isRoundExplicitlySkipped(requestedRoundId)
      ? 'it is present but failed dynamic-config authentication'
      : 'it is absent from the authenticated round set';
  throw StateError(
    'Round $requestedRoundId is not authenticated by voting config: $reason.',
  );
}

String _roundTitle(VotingRoundDetails round) {
  final title = round.title.trim();
  return title.isEmpty ? 'Poll results' : title;
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

bool _textExceedsSingleLine({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required double maxWidth,
}) {
  if (!maxWidth.isFinite || maxWidth <= 0) return false;
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return textPainter.didExceedMaxLines;
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
  return '${zec.toStringAsFixed(2)} ZEC';
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
