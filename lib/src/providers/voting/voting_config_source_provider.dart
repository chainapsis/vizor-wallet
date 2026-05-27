import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_secure_store.dart';
import '../../services/voting/voting_config_loader.dart';

class SavedVotingConfigSource {
  const SavedVotingConfigSource({
    required this.id,
    required this.name,
    required this.sourceUrl,
  });

  final String id;
  final String name;
  final String sourceUrl;

  factory SavedVotingConfigSource.fromJson(Map<String, dynamic> json) {
    return SavedVotingConfigSource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sourceUrl': sourceUrl,
  };

  SavedVotingConfigSource copyWith({String? name, String? sourceUrl}) {
    return SavedVotingConfigSource(
      id: id,
      name: name ?? this.name,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}

class VotingConfigSourceState {
  const VotingConfigSourceState({
    required this.sourceUrl,
    required this.isDefault,
    this.savedSources = const [],
  });

  factory VotingConfigSourceState.defaultSource() {
    return const VotingConfigSourceState(
      sourceUrl: kDefaultStaticVotingConfigSource,
      isDefault: true,
    );
  }

  final String sourceUrl;
  final bool isDefault;
  final List<SavedVotingConfigSource> savedSources;

  StaticVotingConfigSource get staticConfigSource =>
      StaticVotingConfigSource.parse(sourceUrl);

  VotingConfigSourceState copyWith({
    String? sourceUrl,
    bool? isDefault,
    List<SavedVotingConfigSource>? savedSources,
  }) {
    return VotingConfigSourceState(
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isDefault: isDefault ?? this.isDefault,
      savedSources: savedSources ?? this.savedSources,
    );
  }
}

abstract interface class VotingConfigSourceStore {
  Future<String?> readSourceUrl();

  Future<void> writeSourceUrl(String sourceUrl);

  Future<void> resetSourceUrl();

  Future<String?> readSavedSourcesJson();

  Future<void> writeSavedSourcesJson(String savedSourcesJson);
}

final votingConfigSourceStoreProvider = Provider<VotingConfigSourceStore>((
  ref,
) {
  return AppSecureStoreVotingConfigSourceStore(AppSecureStore.instance);
});

class AppSecureStoreVotingConfigSourceStore implements VotingConfigSourceStore {
  const AppSecureStoreVotingConfigSourceStore(this._store);

  final AppSecureStore _store;

  @override
  Future<String?> readSourceUrl() {
    return _store.readPlain(kVotingConfigSourceKey);
  }

  @override
  Future<void> writeSourceUrl(String sourceUrl) {
    return _store.writePlain(kVotingConfigSourceKey, sourceUrl);
  }

  @override
  Future<void> resetSourceUrl() {
    return _store.delete(kVotingConfigSourceKey);
  }

  @override
  Future<String?> readSavedSourcesJson() {
    return _store.readPlain(kVotingConfigSavedSourcesKey);
  }

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) {
    return _store.writePlain(kVotingConfigSavedSourcesKey, savedSourcesJson);
  }
}

class VotingConfigSourceNotifier
    extends AsyncNotifier<VotingConfigSourceState> {
  @override
  Future<VotingConfigSourceState> build() async {
    final store = ref.read(votingConfigSourceStoreProvider);
    final stored = await store.readSourceUrl();
    final savedSources = _decodeSavedSources(
      await store.readSavedSourcesJson(),
    );
    final trimmed = stored?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return VotingConfigSourceState.defaultSource().copyWith(
        savedSources: savedSources,
      );
    }
    return VotingConfigSourceState(
      sourceUrl: trimmed,
      isDefault: false,
      savedSources: savedSources,
    );
  }

  Future<void> setCustom(String sourceUrl) async {
    final trimmed = sourceUrl.trim();
    StaticVotingConfigSource.parse(trimmed);
    await ref.read(votingConfigSourceStoreProvider).writeSourceUrl(trimmed);
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    state = AsyncData(previous.copyWith(sourceUrl: trimmed, isDefault: false));
  }

  Future<void> resetDefault() async {
    await ref.read(votingConfigSourceStoreProvider).resetSourceUrl();
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    state = AsyncData(
      VotingConfigSourceState.defaultSource().copyWith(
        savedSources: previous.savedSources,
      ),
    );
  }

  Future<void> saveSource({
    String? id,
    required String name,
    required String sourceUrl,
  }) async {
    final trimmedUrl = sourceUrl.trim();
    StaticVotingConfigSource.parse(trimmedUrl);
    final trimmedName = _normalizeSavedSourceName(name);
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    final nextSaved = [...previous.savedSources];
    final existingIndex = id == null
        ? -1
        : nextSaved.indexWhere((source) => source.id == id);
    if (existingIndex >= 0) {
      nextSaved[existingIndex] = nextSaved[existingIndex].copyWith(
        name: trimmedName,
        sourceUrl: trimmedUrl,
      );
    } else {
      nextSaved.add(
        SavedVotingConfigSource(
          id: _newSavedSourceId(),
          name: trimmedName,
          sourceUrl: trimmedUrl,
        ),
      );
    }

    final store = ref.read(votingConfigSourceStoreProvider);
    await store.writeSavedSourcesJson(_encodeSavedSources(nextSaved));
    await store.writeSourceUrl(trimmedUrl);
    state = AsyncData(
      VotingConfigSourceState(
        sourceUrl: trimmedUrl,
        isDefault: false,
        savedSources: nextSaved,
      ),
    );
  }

  Future<void> deleteSavedSource(String id) async {
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    SavedVotingConfigSource? target;
    for (final source in previous.savedSources) {
      if (source.id == id) {
        target = source;
        break;
      }
    }
    if (target == null) return;

    final nextSaved = [
      for (final source in previous.savedSources)
        if (source.id != id) source,
    ];
    final store = ref.read(votingConfigSourceStoreProvider);
    await store.writeSavedSourcesJson(_encodeSavedSources(nextSaved));

    if (_sameSourceUrl(previous.sourceUrl, target.sourceUrl)) {
      await store.resetSourceUrl();
      state = AsyncData(
        VotingConfigSourceState.defaultSource().copyWith(
          savedSources: nextSaved,
        ),
      );
      return;
    }

    state = AsyncData(previous.copyWith(savedSources: nextSaved));
  }
}

List<SavedVotingConfigSource> _decodeSavedSources(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return const [];

  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];

  final sources = <SavedVotingConfigSource>[];
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    final source = SavedVotingConfigSource.fromJson(item);
    if (source.id.isEmpty ||
        source.name.trim().isEmpty ||
        source.sourceUrl.trim().isEmpty) {
      continue;
    }
    try {
      StaticVotingConfigSource.parse(source.sourceUrl.trim());
    } on StaticVotingConfigSourceMalformed {
      continue;
    }
    sources.add(
      SavedVotingConfigSource(
        id: source.id,
        name: _normalizeSavedSourceName(source.name),
        sourceUrl: source.sourceUrl.trim(),
      ),
    );
  }
  return sources;
}

String _encodeSavedSources(List<SavedVotingConfigSource> sources) {
  return jsonEncode(sources.map((source) => source.toJson()).toList());
}

String _normalizeSavedSourceName(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? 'Custom source' : trimmed;
}

String _newSavedSourceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

bool _sameSourceUrl(String lhs, String rhs) {
  try {
    final left = StaticVotingConfigSource.parse(lhs.trim());
    final right = StaticVotingConfigSource.parse(rhs.trim());
    return left.uri == right.uri && left.sha256Hex == right.sha256Hex;
  } on StaticVotingConfigSourceMalformed {
    return lhs.trim() == rhs.trim();
  }
}

final votingConfigSourceProvider =
    AsyncNotifierProvider<VotingConfigSourceNotifier, VotingConfigSourceState>(
      VotingConfigSourceNotifier.new,
    );
