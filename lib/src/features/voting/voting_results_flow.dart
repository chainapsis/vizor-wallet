import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/voting/voting_config_provider.dart';
import '../../providers/voting/voting_service_providers.dart';
import '../../providers/voting/voting_session_provider.dart';
import '../../providers/voting/voting_state.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_models.dart';
import 'voting_error_messages.dart';
import 'voting_flow_models.dart';
import 'voting_poll_ordering.dart';

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

/// One renderable state of the results screen. Produced by
/// [VotingResultsFlow]; rendered by the form-factor screens.
sealed class VotingResultsView {
  const VotingResultsView();
}

class VotingResultsLoading extends VotingResultsView {
  const VotingResultsLoading();
}

/// Terminal message (load errors, missing round details).
class VotingResultsMessage extends VotingResultsView {
  const VotingResultsMessage(this.message);

  final String message;
}

/// The tally is not published yet; the flow keeps polling while this state
/// is shown.
class VotingResultsPending extends VotingResultsView {
  const VotingResultsPending();
}

class VotingResultsContent extends VotingResultsView {
  const VotingResultsContent({
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.entries,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final List<VotingResultEntryView> entries;
}

class VotingResultEntryView {
  const VotingResultEntryView({
    required this.proposal,
    required this.tally,
    required this.selectedChoice,
  });

  final VotingProposalView proposal;
  final Map<int, num> tally;
  final int? selectedChoice;
}

typedef VotingResultsBuilder =
    Widget Function(BuildContext context, VotingResultsView view);

/// Shared state machine behind the results screens: watches the round tally,
/// re-polls while the tally is still being computed, and derives per-proposal
/// tallies plus the caller's own recorded choice.
class VotingResultsFlow extends ConsumerStatefulWidget {
  const VotingResultsFlow({
    super.key,
    required this.roundId,
    required this.builder,
  });

  final String roundId;
  final VotingResultsBuilder builder;

  @override
  ConsumerState<VotingResultsFlow> createState() => _VotingResultsFlowState();
}

class _VotingResultsFlowState extends ConsumerState<VotingResultsFlow> {
  Timer? _pendingTallyRefreshTimer;

  @override
  void didUpdateWidget(covariant VotingResultsFlow oldWidget) {
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
    final view = tally.when(
      skipLoadingOnRefresh: false,
      loading: () => const VotingResultsLoading(),
      error: (error, _) {
        final round = session.value?.round;
        if (round != null &&
            _roundIsTallying(round) &&
            _isTallyNotReadyError(error)) {
          return _pendingResults();
        }
        _clearPendingTallyRefresh();
        return VotingResultsMessage(
          "Couldn't load results: ${friendlyVotingErrorMessage(error)}",
        );
      },
      data: (result) {
        final round = session.value?.round;
        if (round == null) {
          _clearPendingTallyRefresh();
          if (session.hasError) {
            return VotingResultsMessage(
              "Couldn't load voting round details: "
              "${friendlyVotingErrorMessage(session.error!)}",
            );
          }
          return const VotingResultsLoading();
        }
        final proposals = proposalsFromRound(round);
        if (_isTallying(result.rawJson)) {
          return _pendingResults();
        }
        _clearPendingTallyRefresh();
        return VotingResultsContent(
          title: _roundTitle(round),
          snapshotHeight: round.snapshotHeight,
          description: _roundDescription(round) ?? '',
          forumUri: votingRoundForumUriFromJson(round.rawJson),
          entries: [
            for (final proposal in proposals)
              VotingResultEntryView(
                proposal: proposal,
                tally: _proposalTally(result.rawJson, proposal.id),
                selectedChoice: _selectedChoiceForProposal(
                  session.value,
                  proposal.id,
                ),
              ),
          ],
        );
      },
    );
    return widget.builder(context, view);
  }

  VotingResultsView _pendingResults() {
    _schedulePendingTallyRefresh();
    return const VotingResultsPending();
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
