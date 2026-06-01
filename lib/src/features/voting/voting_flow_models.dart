import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_secure_store.dart';
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
}

class VotingDraftNotifier extends Notifier<VotingDraftState> {
  VotingDraftNotifier(this.key);

  /// Round/account owner for this in-memory draft.
  final VotingSessionKey key;
  Future<VotingDraftState>? _loadFuture;
  bool _loaded = false;
  bool _mutatedBeforeLoad = false;

  @override
  VotingDraftState build() {
    unawaited(ensureLoaded());
    return const VotingDraftState();
  }

  Future<VotingDraftState> ensureLoaded() {
    if (_loaded) return Future.value(state);
    return _loadFuture ??= _loadPersisted();
  }

  void setChoice(int proposalId, int choice) {
    _mutatedBeforeLoad = !_loaded;
    final next = state.setChoice(proposalId, choice);
    state = next;
    unawaited(_persist(next));
  }

  void clearChoice(int proposalId) {
    _mutatedBeforeLoad = !_loaded;
    final next = state.clearChoice(proposalId);
    state = next;
    unawaited(_persist(next));
  }

  Future<VotingDraftState> _loadPersisted() async {
    final persisted = await ref.read(votingDraftPersistenceProvider).load(key);
    _loaded = true;
    if (!_mutatedBeforeLoad && ref.mounted) {
      state = persisted;
      return persisted;
    }
    return state;
  }

  Future<void> _persist(VotingDraftState draft) {
    return ref.read(votingDraftPersistenceProvider).save(key, draft);
  }
}

final votingDraftProvider =
    NotifierProvider.family<
      VotingDraftNotifier,
      VotingDraftState,
      VotingSessionKey
    >(VotingDraftNotifier.new);

abstract interface class VotingDraftPersistence {
  Future<VotingDraftState> load(VotingSessionKey key);

  Future<void> save(VotingSessionKey key, VotingDraftState draft);
}

final votingDraftPersistenceProvider = Provider<VotingDraftPersistence>(
  (_) => const SecureVotingDraftPersistence(),
);

class SecureVotingDraftPersistence implements VotingDraftPersistence {
  const SecureVotingDraftPersistence();

  static const _keyPrefix = 'zcash_voting_draft_votes_';

  @override
  Future<VotingDraftState> load(VotingSessionKey key) async {
    final raw = await AppSecureStore.instance.readPlain(_storageKey(key));
    if (raw == null || raw.isEmpty) return const VotingDraftState();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return const VotingDraftState();
    final choices = <int, int>{};
    for (final entry in decoded.entries) {
      final proposalId = int.tryParse(entry.key);
      final choice = entry.value;
      if (proposalId != null && choice is int) {
        choices[proposalId] = choice;
      }
    }
    return VotingDraftState(choices: choices);
  }

  @override
  Future<void> save(VotingSessionKey key, VotingDraftState draft) async {
    final storageKey = _storageKey(key);
    if (draft.choices.isEmpty) {
      await AppSecureStore.instance.delete(storageKey);
      return;
    }
    final encoded = <String, int>{
      for (final entry in draft.choices.entries) '${entry.key}': entry.value,
    };
    await AppSecureStore.instance.writePlain(storageKey, jsonEncode(encoded));
  }

  static String _storageKey(VotingSessionKey key) =>
      '$_keyPrefix${key.accountUuid}|${key.roundId}';
}

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
    if (value is num) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      throw FormatException('$key must be an integer');
    }
    return int.parse(value.toString());
  }
  return null;
}
