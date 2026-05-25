import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';
import '../features/receive/address_label_policy.dart';
import 'hidden_memos_provider.dart' show appSecureStoreProvider;

/// In-memory state: maps accountUuid → (address → label).
class AddressLabelsState {
  const AddressLabelsState(this._data);

  final Map<String, Map<String, String>> _data;

  /// Returns the label for [address] under [accountUuid], or null if absent.
  String? labelFor(String accountUuid, String address) {
    return _data[accountUuid]?[address];
  }

  AddressLabelsState _withUpdated(
    String accountUuid,
    Map<String, String> labels,
  ) {
    final next = Map<String, Map<String, String>>.from(_data);
    if (labels.isEmpty) {
      next.remove(accountUuid);
    } else {
      next[accountUuid] = labels;
    }
    return AddressLabelsState(next);
  }

  /// JSON-encodable form: `{ accountUuid: { address: label } }`.
  Map<String, Map<String, String>> toSerializable() {
    return _data.map((k, v) => MapEntry(k, Map<String, String>.from(v)));
  }
}

class AddressLabelsNotifier extends Notifier<AddressLabelsState> {
  @override
  AddressLabelsState build() {
    // Self-initialize from storage. Watchers automatically rebuild when the
    // load completes, so consumers never see a stale empty map just because
    // nobody called load() explicitly.
    Future.microtask(load);
    return const AddressLabelsState({});
  }

  AppSecureStore get _store => ref.read(appSecureStoreProvider);

  // Bumped on every mutation. A [load] that started before a mutation must not
  // clobber the newer in-memory state when its async read resolves — this
  // matters because [build] kicks off load() fire-and-forget while a caller may
  // already be mutating.
  int _mutationGen = 0;

  /// Loads persisted address labels from storage into state. Public and
  /// idempotent: safe to call repeatedly; each call re-reads storage and
  /// replaces in-memory state with the persisted snapshot. If a mutation
  /// ([setLabel]/[removeLabel]) lands while the read is in flight, the load
  /// result is discarded so the fresher mutation wins.
  Future<void> load() async {
    final startedGen = _mutationGen;
    final raw = await _store.readPlain(kAddressLabelsKey);
    if (_mutationGen != startedGen) return;
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final data = decoded.map(
        (accountUuid, v) => MapEntry(
          accountUuid,
          (v as Map<String, dynamic>).map(
            (address, label) => MapEntry(address, label as String),
          ),
        ),
      );
      state = AddressLabelsState(data);
    } catch (_) {
      // Corrupt data: leave state empty rather than crashing.
    }
  }

  /// Sets [label] for [address] under [accountUuid] and persists.
  /// Applies [normalizeAddressLabel]; a null/blank normalized result removes
  /// the entry (same as calling [removeLabel]).
  Future<void> setLabel({
    required String accountUuid,
    required String address,
    required String label,
  }) async {
    final normalized = normalizeAddressLabel(label);
    if (normalized == null) {
      await removeLabel(accountUuid: accountUuid, address: address);
      return;
    }
    _mutationGen++;
    final current = Map<String, String>.from(
      state._data[accountUuid] ?? const {},
    );
    current[address] = normalized;
    state = state._withUpdated(accountUuid, current);
    await _persist();
  }

  /// Removes the label for [address] under [accountUuid] and persists.
  Future<void> removeLabel({
    required String accountUuid,
    required String address,
  }) async {
    _mutationGen++;
    final current = Map<String, String>.from(
      state._data[accountUuid] ?? const {},
    );
    current.remove(address);
    state = state._withUpdated(accountUuid, current);
    await _persist();
  }

  Future<void> _persist() async {
    await _store.writePlain(
      kAddressLabelsKey,
      jsonEncode(state.toSerializable()),
    );
  }
}

final addressLabelsProvider =
    NotifierProvider<AddressLabelsNotifier, AddressLabelsState>(
  AddressLabelsNotifier.new,
);
