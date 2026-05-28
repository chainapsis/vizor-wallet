import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/voting.dart' as rust_voting;
import '../../services/voting/voting_models.dart';
import '../../providers/voting/voting_state.dart';

const int _minProposalId = 1;
const int _maxProposalId = 15;

class VotingProposalView {
  const VotingProposalView({
    required this.id,
    required this.title,
    required this.description,
    required this.options,
  });

  final int id;
  final String title;
  final String description;
  final List<VotingOptionView> options;
}

class VotingOptionView {
  const VotingOptionView({required this.index, required this.label});

  final int index;
  final String label;
}

/// Stable owner key for voting UI state that must not cross accounts.
///
/// [roundId] is the vote round identifier used by Rust recovery state, and
/// [accountUuid] is the account pinned when the voting session was created.
class VotingSessionKey {
  const VotingSessionKey({required this.roundId, required this.accountUuid});

  final String roundId;
  final String accountUuid;

  @override
  bool operator ==(Object other) {
    return other is VotingSessionKey &&
        other.roundId == roundId &&
        other.accountUuid == accountUuid;
  }

  @override
  int get hashCode => Object.hash(roundId, accountUuid);
}

class VotingDraftState {
  const VotingDraftState({this.choices = const {}});

  final Map<int, int> choices;

  bool get isEmpty => choices.isEmpty;

  VotingDraftState setChoice(int proposalId, int choice) {
    return VotingDraftState(choices: {...choices, proposalId: choice});
  }

  VotingDraftState clearChoice(int proposalId) {
    final nextChoices = Map<int, int>.from(choices)..remove(proposalId);
    return VotingDraftState(choices: nextChoices);
  }

  List<rust_voting.ApiDraftVote> toDraftVotes(
    List<VotingProposalView> proposals, {
    bool singleShare = false,
  }) {
    return [
      for (final proposal in proposals)
        if (choices[proposal.id] != null)
          rust_voting.ApiDraftVote(
            proposalId: proposal.id,
            choice: choices[proposal.id]!,
            numOptions: proposal.options.length,
            vcTreePosition: BigInt.zero,
            singleShare: singleShare,
          ),
    ];
  }
}

class VotingDraftNotifier extends Notifier<VotingDraftState> {
  VotingDraftNotifier(this.key);

  /// Round/account owner for this in-memory draft.
  final VotingSessionKey key;

  @override
  VotingDraftState build() => const VotingDraftState();

  void setChoice(int proposalId, int choice) {
    state = state.setChoice(proposalId, choice);
  }

  void clearChoice(int proposalId) {
    state = state.clearChoice(proposalId);
  }
}

final votingDraftProvider =
    NotifierProvider.family<
      VotingDraftNotifier,
      VotingDraftState,
      VotingSessionKey
    >(VotingDraftNotifier.new);

List<VotingProposalView> proposalsFromRound(VotingRoundDetails round) {
  return proposalsFromJson(round.rawJson);
}

List<VotingProposalView> proposalsFromJson(Map<String, dynamic> json) {
  final value =
      json['proposals'] ?? json['questions'] ?? json['ballot'] ?? const [];
  final values = value is List ? value : const [];
  return [
    for (var i = 0; i < values.length; i++)
      _proposalFromJson(_objectFromValue(values[i]), fallbackId: i),
  ];
}

VotingRoundSummary roundSummaryFromDetails(VotingRoundDetails details) {
  return VotingRoundSummary(
    roundId: details.roundId,
    title: details.title,
    status: details.status,
    rawJson: details.rawJson,
  );
}

VotingProposalView _proposalFromJson(
  Map<String, dynamic> json, {
  required int fallbackId,
}) {
  final id = _proposalIdFromJson(json);
  final optionsJson = json['options'] ?? json['choices'] ?? const [];
  final options = optionsJson is List
      ? [
          for (var i = 0; i < optionsJson.length; i++)
            _optionFromJson(optionsJson[i], fallbackIndex: i),
        ]
      : const <VotingOptionView>[];
  return VotingProposalView(
    id: id,
    title:
        _stringFromJson(json, const ['title', 'name', 'question']) ??
        'Proposal ${fallbackId + 1}',
    description:
        _stringFromJson(json, const ['description', 'body', 'summary']) ?? '',
    options: options.isEmpty
        ? const [
            VotingOptionView(index: 0, label: 'Yes'),
            VotingOptionView(index: 1, label: 'No'),
          ]
        : options,
  );
}

int _proposalIdFromJson(Map<String, dynamic> json) {
  final id = _intFromJson(json, const ['proposal_id', 'proposalId', 'id']);
  if (id == null) {
    throw const FormatException('Missing required int: proposal_id');
  }
  if (id < _minProposalId || id > _maxProposalId) {
    throw FormatException(
      'proposal_id must be $_minProposalId..$_maxProposalId, got $id',
    );
  }
  return id;
}

VotingOptionView _optionFromJson(Object? value, {required int fallbackIndex}) {
  if (value is String) {
    return VotingOptionView(index: fallbackIndex, label: value);
  }
  final json = _objectFromValue(value);
  return VotingOptionView(
    index: _intFromJson(json, const ['index', 'choice', 'id']) ?? fallbackIndex,
    label:
        _stringFromJson(json, const ['label', 'title', 'name']) ??
        'Option ${fallbackIndex + 1}',
  );
}

Map<String, dynamic> _objectFromValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

String? _stringFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    return value.toString();
  }
  return null;
}

int? _intFromJson(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
  return null;
}
