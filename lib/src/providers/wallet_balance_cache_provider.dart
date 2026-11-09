import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/storage/wallet_balance_cache.dart';
import '../rust/api/balance_cache.dart' as rust_cache;
import '../rust/api/sync.dart' as rust_sync;

final walletBalanceCacheProvider = Provider((ref) {
  final store = WalletBalanceCacheStore();
  ref.onDispose(store.discardPending);
  return store;
});

/// Serial, coalescing writes. Destructive mutations suspend the queue before
/// their first await and drain accepted I/O before deleting wallet data.
class WalletBalanceCacheStore {
  final _pending = <(String, String, String), CachedWalletBalance>{};
  Future<void>? _writing;
  int _suspensions = 0;

  Future<CachedWalletBalance?> load({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) => readCachedWalletBalance(
    dbPath: dbPath,
    network: network,
    accountUuid: accountUuid,
  );

  void accept({
    required String dbPath,
    required String network,
    required String accountUuid,
    required rust_sync.WalletBalance balance,
  }) {
    if (_suspensions > 0 ||
        balance.availability != rust_sync.WalletBalanceAvailability.available) {
      return;
    }
    _pending[(dbPath, network, accountUuid)] = CachedWalletBalance(
      balance,
      DateTime.now().toUtc(),
    );
    _writing ??= _flush();
  }

  Future<void> _flush() async {
    // Install _writing before the first bridge call can finish or throw.
    await Future<void>.value();
    try {
      while (_pending.isNotEmpty && _suspensions == 0) {
        final key = _pending.keys.first;
        final snapshot = _pending.remove(key)!;
        try {
          await write(key.$1, key.$2, key.$3, snapshot.encode());
        } catch (error) {
          log('Balance cache: save failed: $error');
        }
      }
    } finally {
      _writing = null;
    }
  }

  Future<void> write(
    String dbPath,
    String network,
    String accountUuid,
    String payload,
  ) => rust_cache.saveBalanceCache(
    dbPath: dbPath,
    network: network,
    accountUuid: accountUuid,
    payload: payload,
  );

  void discardPending() => _pending.clear();

  Future<void> suspendAndDrain() {
    ++_suspensions;
    discardPending();
    return _writing ?? Future<void>.value();
  }

  void resume() {
    assert(_suspensions > 0);
    --_suspensions;
  }
}
