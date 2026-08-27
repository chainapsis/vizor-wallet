import 'dart:convert';
import 'dart:typed_data';

import '../../core/private_state_sync/private_state_models.dart';
import '../../core/private_state_sync/private_state_object_repository.dart';
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import 'voting_resume_plan.dart';

const _votingCompletionSchemaVersion = 1;
const _maxVotingCompletionChoices = 1024;

class VotingCompletionRecord {
  VotingCompletionRecord({
    required this.roundId,
    required this.completedAtSeconds,
    required Map<int, int?> choicesByProposalId,
  }) : choicesByProposalId = Map.unmodifiable(
         Map.fromEntries(
           choicesByProposalId.entries.toList()
             ..sort((left, right) => left.key.compareTo(right.key)),
         ),
       ) {
    _validate();
  }

  final String roundId;
  final int? completedAtSeconds;
  final Map<int, int?> choicesByProposalId;

  DateTime? get completedAt => completedAtSeconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          completedAtSeconds! * 1000,
          isUtc: true,
        );

  static VotingCompletionRecord? fromRoundPlan({
    required String roundId,
    required rust_wire.RoundPlanView? roundPlan,
  }) {
    if (!hasCompletedVoteForDisplay(roundPlan)) return null;
    final display = roundPlan?.completedVoteDisplay;
    if (display == null) return null;
    return VotingCompletionRecord(
      roundId: roundId,
      completedAtSeconds: display.votedAt?.toInt(),
      choicesByProposalId: {
        for (final choice in display.choices) choice.proposalId: choice.choice,
      },
    );
  }

  Uint8List encode() {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': _votingCompletionSchemaVersion,
          'round_id': roundId,
          'completed_at_seconds': completedAtSeconds,
          'choices': [
            for (final entry in choicesByProposalId.entries)
              {'proposal_id': entry.key, 'choice': entry.value},
          ],
        }),
      ),
    );
  }

  static VotingCompletionRecord decode(
    Uint8List bytes, {
    required String expectedRoundId,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on Object catch (error) {
      throw PrivateStateProtocolException(
        'Voting completion payload is not valid UTF-8 JSON: $error',
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != _votingCompletionSchemaVersion ||
        decoded['round_id'] != expectedRoundId) {
      throw const PrivateStateProtocolException(
        'Voting completion payload has an invalid schema or round ID.',
      );
    }
    final completedAt = decoded['completed_at_seconds'];
    if (completedAt != null && completedAt is! int) {
      throw const PrivateStateProtocolException(
        'Voting completion timestamp must be integer seconds.',
      );
    }
    final choicesJson = decoded['choices'];
    if (choicesJson is! List ||
        choicesJson.length > _maxVotingCompletionChoices) {
      throw const PrivateStateProtocolException(
        'Voting completion choices are missing or exceed the limit.',
      );
    }
    final choices = <int, int?>{};
    for (final value in choicesJson) {
      if (value is! Map<String, dynamic>) {
        throw const PrivateStateProtocolException(
          'Voting completion choice has an invalid shape.',
        );
      }
      final proposalId = value['proposal_id'];
      final choice = value['choice'];
      if (proposalId is! int ||
          proposalId < 0 ||
          (choice != null && (choice is! int || choice < 0)) ||
          choices.containsKey(proposalId)) {
        throw const PrivateStateProtocolException(
          'Voting completion choice is invalid or duplicated.',
        );
      }
      choices[proposalId] = choice as int?;
    }
    return VotingCompletionRecord(
      roundId: expectedRoundId,
      completedAtSeconds: completedAt as int?,
      choicesByProposalId: choices,
    );
  }

  void _validate() {
    if (roundId.isEmpty || utf8.encode(roundId).length > 480) {
      throw const PrivateStateProtocolException(
        'Voting round ID must contain 1 to 480 UTF-8 bytes.',
      );
    }
    if (completedAtSeconds != null && completedAtSeconds! < 0) {
      throw const PrivateStateProtocolException(
        'Voting completion timestamp must not be negative.',
      );
    }
    if (choicesByProposalId.length > _maxVotingCompletionChoices ||
        choicesByProposalId.entries.any(
          (entry) => entry.key < 0 || (entry.value != null && entry.value! < 0),
        )) {
      throw const PrivateStateProtocolException(
        'Voting completion choices are invalid or exceed the limit.',
      );
    }
  }
}

/// Immutable completion adapter. Local chain/recovery state remains the source
/// of truth; this object only restores cross-installation presentation state.
class VotingPrivateStateSync {
  const VotingPrivateStateSync(
    this._repository, {
    void Function(PrivateStateAccount account, VotingCompletionRecord record)?
    onCompletionObserved,
  }) : _onCompletionObserved = onCompletionObserved;

  final PrivateStateObjectRepository _repository;
  final void Function(
    PrivateStateAccount account,
    VotingCompletionRecord record,
  )?
  _onCompletionObserved;

  Future<VotingCompletionRecord?> readCompletion({
    required PrivateStateAccount account,
    required String roundId,
  }) async {
    final result = await _repository.read(account: account, key: _key(roundId));
    final record = switch (result) {
      PrivateStateReadAbsent() => null,
      PrivateStateReadFound(:final plaintext) => VotingCompletionRecord.decode(
        plaintext,
        expectedRoundId: roundId,
      ),
    };
    if (record != null) _onCompletionObserved?.call(account, record);
    return record;
  }

  /// Publishes once. A concurrent winner is read and returned without merging
  /// or overwriting immutable voting history.
  Future<VotingCompletionRecord> publishCompletion({
    required PrivateStateAccount account,
    required VotingCompletionRecord record,
  }) async {
    final result = await _repository.create(
      account: account,
      key: _key(record.roundId),
      plaintext: record.encode(),
    );
    if (result is PrivateStateCreated) {
      _onCompletionObserved?.call(account, record);
      return record;
    }
    final existing = await readCompletion(
      account: account,
      roundId: record.roundId,
    );
    if (existing == null) {
      throw const PrivateStateProtocolException(
        'Voting completion conflicted but no remote object was found.',
      );
    }
    return existing;
  }

  PrivateStateObjectKey _key(String roundId) {
    return PrivateStateObjectKey(
      namespace: PrivateStateNamespace.votingCompletion,
      itemKey: 'round-v1:$roundId',
    );
  }
}
