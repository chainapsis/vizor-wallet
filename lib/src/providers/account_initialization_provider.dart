import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AccountInitializationKind { created, restored, unknown }

enum InitialAccountReads { pending, available, unavailable }

/// Session-only presentation evidence. It never grants spendability or changes
/// a birthday, scan range, credential, or persisted account record.
class AccountInitialization {
  AccountInitialization(this.kind)
    : token = Object(),
      scanStarted = false,
      scanCompleted = false,
      reads = InitialAccountReads.pending;

  const AccountInitialization._(
    this.kind,
    this.token,
    this.scanStarted,
    this.scanCompleted,
    this.reads,
  );

  final AccountInitializationKind kind;
  final Object token;
  final bool scanStarted;
  final bool scanCompleted;
  final InitialAccountReads reads;

  AccountInitialization copyWith({
    bool? scanStarted,
    bool? scanCompleted,
    InitialAccountReads? reads,
  }) => AccountInitialization._(
    kind,
    token,
    scanStarted ?? this.scanStarted,
    scanCompleted ?? this.scanCompleted,
    reads ?? this.reads,
  );
}

class AccountInitializationNotifier
    extends Notifier<Map<String, AccountInitialization>> {
  @override
  Map<String, AccountInitialization> build() => const {};

  void register(String uuid, AccountInitializationKind kind) {
    if (state.containsKey(uuid)) return;
    state = {...state, uuid: AccountInitialization(kind)};
  }

  /// Capture before starting a stream. A prior stream cannot complete accounts
  /// created later, or a replacement wallet that happens to reuse a UUID.
  Map<String, Object> pendingTokens() => {
    for (final entry in state.entries)
      if (entry.value.reads != InitialAccountReads.available)
        entry.key: entry.value.token,
  };

  void observeScan(Map<String, Object> tokens, {required bool completed}) {
    final next = {...state};
    var changed = false;
    for (final entry in tokens.entries) {
      final current = state[entry.key];
      if (current == null ||
          !identical(current.token, entry.value) ||
          current.reads == InitialAccountReads.available ||
          (current.scanStarted && (!completed || current.scanCompleted))) {
        continue;
      }
      next[entry.key] = current.copyWith(
        scanStarted: true,
        scanCompleted: completed || current.scanCompleted,
      );
      changed = true;
    }
    if (changed) state = next;
  }

  void reportReads(String uuid, Object? token, {required bool available}) {
    final current = state[uuid];
    if (current == null ||
        !identical(current.token, token) ||
        !current.scanCompleted ||
        current.reads == InitialAccountReads.available) {
      return;
    }
    final reads = available
        ? InitialAccountReads.available
        : InitialAccountReads.unavailable;
    if (current.reads != reads) {
      state = {...state, uuid: current.copyWith(reads: reads)};
    }
  }

  void remove(String uuid) {
    if (state.containsKey(uuid)) state = {...state}..remove(uuid);
  }

  void clear() => state = const {};
}

final accountInitializationProvider =
    NotifierProvider<
      AccountInitializationNotifier,
      Map<String, AccountInitialization>
    >(AccountInitializationNotifier.new);
