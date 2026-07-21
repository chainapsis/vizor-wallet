import 'dart:async';

class IronwoodMigrationAccountRevokedException implements Exception {
  const IronwoodMigrationAccountRevokedException(this.accountUuid);

  final String accountUuid;

  @override
  String toString() =>
      'Ironwood migration is stopping for account $accountUuid.';
}

class IronwoodMigrationAccountRevocation {
  IronwoodMigrationAccountRevocation._(
    this._registry,
    this._key,
    this._token, {
    bool finished = false,
  }) : _finished = finished;

  final IronwoodMigrationOperationRegistry _registry;
  final String _key;
  final Object _token;
  bool _finished;

  void commit() {
    if (_finished) return;
    _finished = true;
    _registry._commitRevocation(_key, _token);
  }

  void rollback() {
    if (_finished) return;
    _finished = true;
    _registry._rollbackRevocation(_key, _token);
  }
}

/// Serializes migration work per account and provides an account-deletion
/// barrier. A committed revocation remains process-local so late callbacks
/// cannot restart work for an account that no longer exists.
class IronwoodMigrationOperationRegistry {
  IronwoodMigrationOperationRegistry();

  static final instance = IronwoodMigrationOperationRegistry();

  final Map<String, Future<void>> _tails = {};
  final Map<String, Object> _revocations = {};
  final Set<String> _committedRevocations = {};

  Future<T> run<T>({
    required String network,
    required String accountUuid,
    required Future<T> Function() operation,
  }) async {
    final key = _key(network, accountUuid);
    if (_revocations.containsKey(key)) {
      throw IronwoodMigrationAccountRevokedException(accountUuid);
    }

    final previous = _tails[key] ?? Future<void>.value();
    final release = Completer<void>();
    final current = previous.then((_) => release.future);
    _tails[key] = current;

    await previous;
    try {
      if (_revocations.containsKey(key)) {
        throw IronwoodMigrationAccountRevokedException(accountUuid);
      }
      return await operation();
    } finally {
      release.complete();
      if (identical(_tails[key], current)) {
        _tails.remove(key);
      }
    }
  }

  Future<IronwoodMigrationAccountRevocation> revokeAndWait({
    required String network,
    required String accountUuid,
  }) async {
    final key = _key(network, accountUuid);
    final existingToken = _revocations[key];
    if (existingToken != null && _committedRevocations.contains(key)) {
      await (_tails[key] ?? Future<void>.value());
      return IronwoodMigrationAccountRevocation._(
        this,
        key,
        existingToken,
        finished: true,
      );
    }
    if (existingToken != null) {
      throw StateError(
        'Ironwood migration is already stopping for account $accountUuid.',
      );
    }

    final token = Object();
    _revocations[key] = token;
    await (_tails[key] ?? Future<void>.value());
    return IronwoodMigrationAccountRevocation._(this, key, token);
  }

  void _rollbackRevocation(String key, Object token) {
    if (identical(_revocations[key], token)) {
      _revocations.remove(key);
      _committedRevocations.remove(key);
    }
  }

  void _commitRevocation(String key, Object token) {
    if (identical(_revocations[key], token)) {
      _committedRevocations.add(key);
    }
  }

  String _key(String network, String accountUuid) => '$network:$accountUuid';
}
