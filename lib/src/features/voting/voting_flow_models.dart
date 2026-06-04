import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_secure_store.dart';
import '../../providers/voting/voting_state.dart';
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;

const int _minProposalId = 1;
const int _maxProposalId = 15;
const List<String> _forumUrlKeys = [
  'discussion_url',
  'discussionUrl',
  'discussionURL',
  'discussion_link',
  'discussionLink',
  'discussion',
  'forum_url',
  'forumUrl',
  'forumURL',
  'forum_link',
  'forumLink',
  'forum',
  'thread_url',
  'threadUrl',
  'thread_link',
  'threadLink',
  'topic_url',
  'topicUrl',
  'topic_link',
  'topicLink',
];
const List<String> _proposalForumUrlKeys = [..._forumUrlKeys, 'url', 'link'];
const List<String> _forumMetadataContainerKeys = [
  'metadata',
  'meta',
  'links',
  'resources',
];

class VotingProposalView {
  const VotingProposalView({
    required this.id,
    required this.title,
    required this.description,
    required this.options,
    this.zipNumber = '',
    this.forumUrl = '',
  });

  final int id;
  final String title;
  final String description;
  final List<VotingOptionView> options;
  final String zipNumber;
  final String forumUrl;

  List<String> get zipBadges {
    final explicitBadges = votingZipBadgesFromZipNumber(zipNumber);
    if (explicitBadges.isNotEmpty) return explicitBadges;
    return votingZipBadgesFromText('$title $description');
  }

  Uri? get forumUri => votingForumUriFromString(forumUrl);

  bool get hasDisplayMetadata => zipBadges.isNotEmpty || forumUri != null;
}

class VotingOptionView {
  const VotingOptionView({
    required this.index,
    required this.label,
    this.description = '',
  });

  final int index;
  final String label;
  final String description;
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

  List<rust_voting.DraftVote> toDraftVotes(
    List<VotingProposalView> proposals, {
    bool singleShare = false,
  }) {
    return [
      for (final proposal in proposals)
        if (choices[proposal.id] != null)
          rust_voting.DraftVote(
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
  Future<VotingDraftState>? _loadFuture;
  Future<void> _saveChain = Future.value();
  bool _loaded = false;
  final Map<int, int?> _pendingBeforeLoad = {};

  @override
  VotingDraftState build() {
    unawaited(ensureLoaded().catchError((Object _, StackTrace _) => state));
    return const VotingDraftState();
  }

  Future<VotingDraftState> ensureLoaded() {
    if (_loaded) return Future.value(state);
    return _loadFuture ??= _loadPersisted();
  }

  void setChoice(int proposalId, int choice) {
    final next = state.setChoice(proposalId, choice);
    state = next;
    if (_loaded) {
      unawaited(_persist(next));
    } else {
      _pendingBeforeLoad[proposalId] = choice;
    }
  }

  void clearChoice(int proposalId) {
    final next = state.clearChoice(proposalId);
    state = next;
    if (_loaded) {
      unawaited(_persist(next));
    } else {
      _pendingBeforeLoad[proposalId] = null;
    }
  }

  Future<void> clearAll() async {
    if (!_loaded) {
      try {
        await ensureLoaded();
      } catch (_) {
        // If persisted draft loading failed, still best-effort delete below.
      }
    }
    _pendingBeforeLoad.clear();
    const next = VotingDraftState();
    state = next;
    await _persist(next);
  }

  Future<VotingDraftState> _loadPersisted() async {
    final persisted = await ref.read(votingDraftPersistenceProvider).load(key);
    _loaded = true;
    final hadPendingBeforeLoad = _pendingBeforeLoad.isNotEmpty;
    final next = hadPendingBeforeLoad
        ? _applyPendingBeforeLoad(persisted)
        : persisted;
    _pendingBeforeLoad.clear();
    if (ref.mounted) {
      state = next;
      if (hadPendingBeforeLoad) {
        unawaited(_persist(next));
      }
    }
    return next;
  }

  Future<void> _persist(VotingDraftState draft) {
    final save = _saveChain.then(
      (_) => ref.read(votingDraftPersistenceProvider).save(key, draft),
    );
    _saveChain = save.catchError((_) {});
    return save;
  }

  VotingDraftState _applyPendingBeforeLoad(VotingDraftState base) {
    var next = base;
    for (final entry in _pendingBeforeLoad.entries) {
      final choice = entry.value;
      next = choice == null
          ? next.clearChoice(entry.key)
          : next.setChoice(entry.key, choice);
    }
    return next;
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

  /// Deletes drafts for an account and rejects later saves for that account in
  /// this process.
  Future<void> deleteForAccount(String accountUuid);
}

final votingDraftPersistenceProvider = Provider<VotingDraftPersistence>(
  (_) => const SecureVotingDraftPersistence(),
);

class SecureVotingDraftPersistence implements VotingDraftPersistence {
  const SecureVotingDraftPersistence();

  static const _keyPrefix = 'zcash_voting_draft_votes_';
  static final _deletedAccountUuids = <String>{};
  static Future<void> _mutationChain = Future.value();

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
    await _runMutation(() async {
      if (_deletedAccountUuids.contains(key.accountUuid)) return;
      final storageKey = _storageKey(key);
      if (draft.choices.isEmpty) {
        await AppSecureStore.instance.delete(storageKey);
        return;
      }
      final encoded = <String, int>{
        for (final entry in draft.choices.entries) '${entry.key}': entry.value,
      };
      await AppSecureStore.instance.writePlain(storageKey, jsonEncode(encoded));
    });
  }

  @override
  Future<void> deleteForAccount(String accountUuid) {
    return _runMutation(() async {
      if (accountUuid.isEmpty) return;
      _deletedAccountUuids.add(accountUuid);
      await AppSecureStore.instance.deletePlainKeysWithPrefix(
        '$_keyPrefix$accountUuid|',
      );
    });
  }

  static String _storageKey(VotingSessionKey key) =>
      '$_keyPrefix${key.accountUuid}|${key.roundId}';

  static Future<void> _runMutation(Future<void> Function() operation) {
    final next = _mutationChain.then((_) => operation());
    _mutationChain = next.catchError((_) {});
    return next;
  }
}

List<VotingProposalView> proposalsFromRound(VotingRoundDetails round) {
  return proposalsFromJson(round.rawJson);
}

List<VotingProposalView> proposalsFromJson(Map<String, dynamic> json) {
  final value = json['proposals'];
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
  final optionsJson = json['options'] ?? const [];
  final options = optionsJson is List
      ? [
          for (var i = 0; i < optionsJson.length; i++)
            _optionFromJson(optionsJson[i], fallbackIndex: i),
        ]
      : const <VotingOptionView>[];
  return VotingProposalView(
    id: id,
    title:
        _stringFromJson(json, const ['title']) ?? 'Proposal ${fallbackId + 1}',
    description: _stringFromJson(json, const ['description']) ?? '',
    zipNumber:
        _stringFromJson(json, const [
          'zip_number',
          'zipNumber',
          'zip_number_string',
          'zipNumberString',
        ])?.trim() ??
        '',
    forumUrl:
        _forumUrlStringFromJson(
          json,
          keys: _proposalForumUrlKeys,
          allowGenericRootLinkKeys: true,
        ) ??
        '',
    options: options.isEmpty
        ? const [
            VotingOptionView(index: 0, label: 'Yes'),
            VotingOptionView(index: 1, label: 'No'),
          ]
        : options,
  );
}

Uri? votingRoundForumUriFromJson(Map<String, dynamic> json) {
  return _forumUriFromJson(
    json,
    keys: _forumUrlKeys,
    allowGenericRootLinkKeys: true,
  );
}

Uri? votingForumUriFromString(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = _externalWebUriFromCandidate(trimmed);
  if (uri != null) return uri;
  final match = RegExp(
    r'''https?://[^\s<>()"']+''',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) return null;
  return _externalWebUriFromCandidate(match.group(0)!);
}

String? _forumUrlStringFromJson(
  Map<String, dynamic> json, {
  required List<String> keys,
  required bool allowGenericRootLinkKeys,
}) {
  return _forumUriFromJson(
    json,
    keys: keys,
    allowGenericRootLinkKeys: allowGenericRootLinkKeys,
  )?.toString();
}

Uri? _forumUriFromJson(
  Map<String, dynamic> json, {
  required List<String> keys,
  required bool allowGenericRootLinkKeys,
}) {
  final direct = votingForumUriFromString(_stringFromJson(json, keys));
  if (direct != null) return direct;

  for (final key in _forumMetadataContainerKeys) {
    final uri = _forumUriFromValue(json[key]);
    if (uri != null) return uri;
  }

  for (final entry in json.entries) {
    if (!_isForumLinkKey(
      entry.key,
      allowGenericLinkKeys: allowGenericRootLinkKeys,
    )) {
      continue;
    }
    final uri = _forumUriFromValue(entry.value);
    if (uri != null) return uri;
  }

  return null;
}

Uri? _forumUriFromValue(Object? value) {
  if (value == null) return null;
  if (value is String) return votingForumUriFromString(value);
  if (value is Map) {
    for (final entry in value.entries) {
      final uri = _forumUriFromValue(entry.value);
      if (uri != null) return uri;
    }
    return null;
  }
  if (value is Iterable) {
    for (final item in value) {
      final uri = _forumUriFromValue(item);
      if (uri != null) return uri;
    }
  }
  return null;
}

Uri? _externalWebUriFromCandidate(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.trim().isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'https' || scheme == 'http' ? uri : null;
}

bool _isForumLinkKey(String key, {required bool allowGenericLinkKeys}) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  if (normalized.contains('forum') ||
      normalized.contains('discussion') ||
      normalized.contains('thread') ||
      normalized.contains('topic')) {
    return true;
  }
  return allowGenericLinkKeys &&
      (normalized == 'url' || normalized == 'link' || normalized == 'href');
}

List<String> votingZipBadgesFromZipNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return const [];

  final parts = trimmed
      .split(RegExp(r'\s*(?:,|;|/|&|\band\b)\s*', caseSensitive: false))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  final normalizedParts = [
    for (final part in parts) _normalizeExplicitZipLabel(part),
  ].whereType<String>().toList(growable: false);
  if (normalizedParts.isNotEmpty) return _dedupe(normalizedParts);

  return votingZipBadgesFromText(trimmed);
}

List<String> votingZipBadgesFromText(String value) {
  final matches = RegExp(
    r'\bZIP[-\s]?\d+\b',
    caseSensitive: false,
  ).allMatches(value);
  return _dedupe([
    for (final match in matches)
      match.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), '-'),
  ]);
}

String? _normalizeExplicitZipLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final prefixed = RegExp(
    r'^ZIP[-\s]?([A-Z0-9]+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (prefixed != null) return 'ZIP-${prefixed.group(1)!.toUpperCase()}';
  if (RegExp(r'^\d+$').hasMatch(trimmed)) return 'ZIP-$trimmed';
  return null;
}

List<String> _dedupe(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

int _proposalIdFromJson(Map<String, dynamic> json) {
  final id = _intFromJson(json, const ['id']);
  if (id == null) {
    throw const FormatException('Missing required int: id');
  }
  if (id < _minProposalId || id > _maxProposalId) {
    throw FormatException(
      'id must be $_minProposalId..$_maxProposalId, got $id',
    );
  }
  return id;
}

VotingOptionView _optionFromJson(Object? value, {required int fallbackIndex}) {
  final json = _objectFromValue(value);
  return VotingOptionView(
    index: _intFromJson(json, const ['index']) ?? fallbackIndex,
    label:
        _stringFromJson(json, const [
          'label',
          'short_title',
          'shortTitle',
          'title',
        ]) ??
        'Option ${fallbackIndex + 1}',
    description: _stringFromJson(json, const ['description']) ?? '',
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
