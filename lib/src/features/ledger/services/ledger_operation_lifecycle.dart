import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final ledgerOperationLifecycleProvider = Provider(
  (ref) => LedgerOperationLifecycle(),
);

final ledgerOperationClaimRegistryProvider = Provider(
  (ref) => LedgerOperationClaimRegistry(),
);

/// Prevents startup/background recovery from consuming an outbox operation
/// while its signing surface still owns draft settlement and result handling.
class LedgerOperationClaimRegistry {
  final Set<String> _claims = {};

  LedgerOperationClaim? tryClaim(String operationId) {
    if (!_claims.add(operationId)) return null;
    return LedgerOperationClaim._(this, operationId);
  }

  void _release(String operationId) => _claims.remove(operationId);
}

class LedgerOperationClaim {
  LedgerOperationClaim._(this._registry, this.operationId);

  final LedgerOperationClaimRegistry _registry;
  final String operationId;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _registry._release(operationId);
  }
}

/// Protects outbox work, including the caller's durable result handling, from
/// wallet deletion on every platform. Device approval is outside this boundary.
/// A destructive operation blocks new work and drains accepted work before
/// deleting accounts or files. Nested calls retain the live owner's permission
/// to finish result handling while deletion waits.
class LedgerOperationLifecycle {
  final Object _zoneKey = Object();
  final Set<Completer<void>> _active = {};
  int _pauseDepth = 0;

  bool get isPaused => _pauseDepth > 0;

  Future<T> run<T>(Future<T> Function() action) async {
    final owner = Zone.current[_zoneKey];
    final nested = owner is Completer<void> && _active.contains(owner);
    if (isPaused && !nested) {
      throw StateError('Ledger operations are paused for wallet changes.');
    }
    final completion = Completer<void>();
    _active.add(completion);
    try {
      return await runZoned(action, zoneValues: {_zoneKey: completion});
    } finally {
      _active.remove(completion);
      completion.complete();
    }
  }

  /// Must be paired with resume, including when the destructive action fails.
  /// Wallet-wide exclusion also covers recovery, which enumerates all accounts.
  Future<void> quiesceAndDrain() async {
    _pauseDepth++;
    // A live owner may start nested result handling while draining. Track and
    // recheck those leases too, even if its caller forgot to await a child.
    while (_active.isNotEmpty) {
      await Future.wait(_active.map((work) => work.future).toList());
    }
  }

  void resume() {
    if (_pauseDepth > 0) _pauseDepth--;
  }
}
