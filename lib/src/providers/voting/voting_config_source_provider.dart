import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_secure_store.dart';
import '../../services/voting/voting_config_loader.dart';

const _votingConfigSourceKey = 'zcash_voting_config_source_url';
const _votingConfigSavedSourcesKey = 'zcash_voting_config_saved_sources';

/// User-saved static config source shown in voting settings.
///
/// The source URL is the hash-pinned static config URL, not the fetched dynamic
/// config URL. Loading still goes through [VotingConfigLoader] validation before
/// any voting services use it.
class SavedVotingConfigSource {
  const SavedVotingConfigSource({
    required this.id,
    required this.name,
    required this.sourceUrl,
  });

  final String id;
  final String name;
  final String sourceUrl;

  factory SavedVotingConfigSource.fromJson(Map<dynamic, dynamic> json) {
    return SavedVotingConfigSource(
      id: _stringJsonField(json, 'id'),
      name: _stringJsonField(json, 'name'),
      sourceUrl: _stringJsonField(json, 'sourceUrl'),
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

/// Selected static voting config source plus the saved source list.
///
/// [isDefault] tracks whether the active source is the bundled default. Saved
/// sources are retained when the user resets the active source back to default.
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

/// Persistence boundary for the active voting config source.
///
/// Config source URLs are not wallet secrets, but they are kept behind this
/// interface so tests can exercise source switching without touching secure
/// storage.
abstract interface class VotingConfigSourceStore {
  /// Reads the active static config source URL override, or null for default.
  Future<String?> readSourceUrl();

  /// Persists the active static config source URL override.
  Future<void> writeSourceUrl(String sourceUrl);

  /// Clears the active override so the bundled source is used.
  Future<void> resetSourceUrl();

  /// Reads the serialized saved source list.
  Future<String?> readSavedSourcesJson();

  /// Persists the serialized saved source list.
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
    return _store.readPlain(_votingConfigSourceKey);
  }

  @override
  Future<void> writeSourceUrl(String sourceUrl) {
    return _store.writePlain(_votingConfigSourceKey, sourceUrl);
  }

  @override
  Future<void> resetSourceUrl() {
    return _store.delete(_votingConfigSourceKey);
  }

  @override
  Future<String?> readSavedSourcesJson() {
    return _store.readPlain(_votingConfigSavedSourcesKey);
  }

  @override
  Future<void> writeSavedSourcesJson(String savedSourcesJson) {
    return _store.writePlain(_votingConfigSavedSourcesKey, savedSourcesJson);
  }
}

/// Owns user selection of the static voting config source.
///
/// Every public mutation validates the source URL before persisting it. The
/// provider never fetches config itself. It only decides which
/// source URL the loader should use.
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
    try {
      parseStaticVotingConfigSource(trimmed);
    } on StaticVotingConfigSourceMalformed {
      await store.resetSourceUrl();
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

  /// Selects a custom source URL without adding it to saved sources.
  Future<void> setCustom(String sourceUrl) async {
    final normalized = parseStaticVotingConfigSource(sourceUrl).raw;
    await ref.read(votingConfigSourceStoreProvider).writeSourceUrl(normalized);
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    state = AsyncData(previous.copyWith(sourceUrl: normalized, isDefault: false));
  }

  /// Uses the bundled default source while preserving saved custom sources.
  Future<void> resetDefault() async {
    await ref.read(votingConfigSourceStoreProvider).resetSourceUrl();
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    state = AsyncData(
      VotingConfigSourceState.defaultSource().copyWith(
        savedSources: previous.savedSources,
      ),
    );
  }

  /// Creates or updates a named saved source and makes it active.
  Future<void> saveSource({
    String? id,
    required String name,
    required String sourceUrl,
  }) async {
    final normalizedUrl = parseStaticVotingConfigSource(sourceUrl).raw;
    final trimmedName = _normalizeSavedSourceName(name);
    final previous = state.value ?? VotingConfigSourceState.defaultSource();
    final nextSaved = [...previous.savedSources];
    final existingIndex = id == null
        ? -1
        : nextSaved.indexWhere((source) => source.id == id);
    if (existingIndex >= 0) {
      nextSaved[existingIndex] = nextSaved[existingIndex].copyWith(
        name: trimmedName,
        sourceUrl: normalizedUrl,
      );
    } else {
      nextSaved.add(
        SavedVotingConfigSource(
          id: _newSavedSourceId(),
          name: trimmedName,
          sourceUrl: normalizedUrl,
        ),
      );
    }

    final store = ref.read(votingConfigSourceStoreProvider);
    await store.writeSavedSourcesJson(_encodeSavedSources(nextSaved));
    await store.writeSourceUrl(normalizedUrl);
    state = AsyncData(
      VotingConfigSourceState(
        sourceUrl: normalizedUrl,
        isDefault: false,
        savedSources: nextSaved,
      ),
    );
  }

  /// Deletes a saved source.
  ///
  /// If the deleted source is currently active, the active source falls back to
  /// the bundled default so the provider never points at an unsaved custom entry
  /// that the user just removed.
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
    if (item is! Map) continue;
    final source = SavedVotingConfigSource.fromJson(item);
    if (source.id.isEmpty ||
        source.name.trim().isEmpty ||
        source.sourceUrl.trim().isEmpty) {
      continue;
    }
    try {
      parseStaticVotingConfigSource(source.sourceUrl.trim());
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

String _stringJsonField(Map<dynamic, dynamic> json, String key) {
  final value = json[key];
  return value is String ? value : '';
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
    final left = parseStaticVotingConfigSource(lhs.trim());
    final right = parseStaticVotingConfigSource(rhs.trim());
    return left.uri == right.uri && left.sha256Hex == right.sha256Hex;
  } on StaticVotingConfigSourceMalformed {
    return lhs.trim() == rhs.trim();
  }
}

final votingConfigSourceProvider =
    AsyncNotifierProvider<VotingConfigSourceNotifier, VotingConfigSourceState>(
      VotingConfigSourceNotifier.new,
    );
