import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';

/// Riverpod provider that exposes the [AppSecureStore] singleton.
/// Override in tests with [AppSecureStore.testing].
final appSecureStoreProvider = Provider<AppSecureStore>(
  (_) => AppSecureStore.instance,
);

/// In-memory state: maps accountUuid → set of hidden memo keys.
class HiddenMemosState {
  const HiddenMemosState(this._data);

  final Map<String, Set<String>> _data;

  /// Returns an unmodifiable copy of the hidden keys for [accountUuid].
  Set<String> keysFor(String accountUuid) {
    final s = _data[accountUuid];
    if (s == null) return const {};
    return Set.unmodifiable(s);
  }

  HiddenMemosState _withUpdated(String accountUuid, Set<String> keys) {
    final next = Map<String, Set<String>>.from(_data);
    if (keys.isEmpty) {
      next.remove(accountUuid);
    } else {
      next[accountUuid] = keys;
    }
    return HiddenMemosState(next);
  }

  /// JSON-encodable form: `{ accountUuid: [key, ...] }`.
  Map<String, List<String>> toSerializable() {
    return _data.map((k, v) => MapEntry(k, v.toList()));
  }
}

class HiddenMemosNotifier extends Notifier<HiddenMemosState> {
  @override
  HiddenMemosState build() {
    // Self-initialize from storage. Watchers automatically rebuild when the
    // load completes, so consumers never see a stale empty set just because
    // nobody called load() explicitly.
    Future.microtask(load);
    return const HiddenMemosState({});
  }

  AppSecureStore get _store => ref.read(appSecureStoreProvider);

  // Bumped on every mutation. A [load] that started before a mutation must not
  // clobber the newer in-memory state when its async read resolves — this
  // matters because [build] kicks off load() fire-and-forget while a caller may
  // already be mutating.
  int _mutationGen = 0;

  /// Loads persisted hidden memos from storage into state. Public and
  /// idempotent: safe to call repeatedly; each call re-reads storage and
  /// replaces in-memory state with the persisted snapshot. If a mutation
  /// ([hide]/[restore]) lands while the read is in flight, the load result is
  /// discarded so the fresher mutation wins.
  Future<void> load() async {
    final startedGen = _mutationGen;
    final raw = await _store.readPlain(kHiddenMemosKey);
    if (_mutationGen != startedGen) return;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = decoded.map(
        (k, v) => MapEntry(k, Set<String>.from(v as List)),
      );
      state = HiddenMemosState(data);
    } catch (_) {
      // Corrupt data: leave state empty rather than crashing.
    }
  }

  /// Marks [key] as hidden for [accountUuid] and persists.
  Future<void> hide({
    required String accountUuid,
    required String key,
  }) async {
    _mutationGen++;
    final current = Set<String>.from(state.keysFor(accountUuid));
    current.add(key);
    state = state._withUpdated(accountUuid, current);
    await _persist();
  }

  /// Removes [key] from the hidden set for [accountUuid] and persists.
  Future<void> restore({
    required String accountUuid,
    required String key,
  }) async {
    _mutationGen++;
    final current = Set<String>.from(state.keysFor(accountUuid));
    current.remove(key);
    state = state._withUpdated(accountUuid, current);
    await _persist();
  }

  Future<void> _persist() async {
    await _store.writePlain(kHiddenMemosKey, jsonEncode(state.toSerializable()));
  }
}

final hiddenMemosProvider =
    NotifierProvider<HiddenMemosNotifier, HiddenMemosState>(
  HiddenMemosNotifier.new,
);
