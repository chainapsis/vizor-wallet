import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'private_state_models.dart';
import 'private_state_remote_store.dart';
import 'private_state_server_verifier.dart';

/// Executable reference for the opaque server contract.
///
/// This implementation is intentionally process-local and is not selected by
/// production providers. It models the atomicity, challenge, signature, CAS,
/// and rollback requirements that an HTTP service must preserve.
class InMemoryPrivateStateRemoteStore implements PrivateStateRemoteStore {
  InMemoryPrivateStateRemoteStore({
    required this.audience,
    required PrivateStateServerVerifier verifier,
    DateTime Function()? now,
    Random? random,
    this.challengeLifetime = const Duration(minutes: 2),
    this.maxOutstandingChallenges = 1024,
  }) : _verifier = verifier,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure() {
    if (challengeLifetime < const Duration(seconds: 1)) {
      throw ArgumentError.value(
        challengeLifetime,
        'challengeLifetime',
        'Must be at least one second.',
      );
    }
    if (maxOutstandingChallenges <= 0) {
      throw ArgumentError.value(
        maxOutstandingChallenges,
        'maxOutstandingChallenges',
        'Must be positive.',
      );
    }
  }

  @override
  final String audience;
  final PrivateStateServerVerifier _verifier;
  final DateTime Function() _now;
  final Random _random;
  final Duration challengeLifetime;
  final int maxOutstandingChallenges;

  final Map<String, _StoredChallenge> _challenges = {};
  final Map<String, PrivateStateEnvelope> _objects = {};
  Future<void> _operationTail = Future.value();

  @override
  Future<PrivateStateServerChallenge> createChallenge({
    required PrivateStateObjectReference object,
  }) {
    return _exclusive(() async {
      await _verifier.verifyObjectReference(object);
      final now = _now().toUtc();
      _challenges.removeWhere(
        (_, challenge) => !challenge.expiresAt.isAfter(now),
      );
      if (_challenges.length >= maxOutstandingChallenges) {
        throw const PrivateStateProtocolException(
          'Reference store challenge capacity exceeded.',
        );
      }
      late String value;
      do {
        value = base64Url
            .encode(List<int>.generate(32, (_) => _random.nextInt(256)))
            .replaceAll('=', '');
      } while (_challenges.containsKey(value));
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        now.add(challengeLifetime).millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      );
      _challenges[value] = _StoredChallenge(
        object: object,
        expiresAt: expiresAt,
      );
      return PrivateStateServerChallenge(
        valueBase64: value,
        expiresAt: expiresAt,
      );
    });
  }

  @override
  Future<PrivateStateRemoteReadResult> get({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
  }) {
    return _exclusive(() async {
      await _consumeAndVerify(
        object: object,
        authorization: authorization,
        method: PrivateStateRequestMethod.get,
      );
      final envelope = _objects[object.objectId];
      return envelope == null
          ? const PrivateStateRemoteAbsent()
          : PrivateStateRemoteFound(envelope);
    });
  }

  @override
  Future<PrivateStateRemotePutResult> put({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
    required PrivateStateVersion? expectedVersion,
  }) {
    return _exclusive(() async {
      await _consumeAndVerify(
        object: object,
        authorization: authorization,
        method: PrivateStateRequestMethod.put,
      );
      final current = _objects[object.objectId];
      if (!_matchesExpectedVersion(current, expectedVersion)) {
        return const PrivateStateRemoteConflict();
      }
      await _verifier.verifyPutTransition(
        envelope: envelope,
        authorization: authorization,
        current: current,
      );
      _objects[object.objectId] = envelope;
      return const PrivateStateRemoteStored();
    });
  }

  Future<void> _consumeAndVerify({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
    required PrivateStateRequestMethod method,
  }) async {
    final challenge = _challenges.remove(authorization.challengeBase64);
    final now = _now().toUtc();
    if (challenge == null ||
        !challenge.expiresAt.isAfter(now) ||
        !authorization.expiresAt.toUtc().isAfter(now) ||
        authorization.expiresAt.toUtc().isAfter(challenge.expiresAt)) {
      throw const PrivateStateProtocolException(
        'Challenge is missing, expired, reused, or has an invalid lifetime.',
      );
    }
    if (!_sameObject(challenge.object, object) ||
        authorization.protocolVersion != object.protocolVersion ||
        authorization.objectId != object.objectId ||
        authorization.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        authorization.method != method ||
        authorization.audience != audience) {
      throw const PrivateStateProtocolException(
        'Authorization does not match the challenged request.',
      );
    }
    await _verifier.verifyAuthorization(authorization);
  }

  bool _matchesExpectedVersion(
    PrivateStateEnvelope? current,
    PrivateStateVersion? expected,
  ) {
    if (current == null || expected == null) {
      return current == null && expected == null;
    }
    return current.revision == expected.revision &&
        current.envelopeHashBase64 == expected.envelopeHashBase64;
  }

  bool _sameObject(
    PrivateStateObjectReference left,
    PrivateStateObjectReference right,
  ) {
    return left.protocolVersion == right.protocolVersion &&
        left.objectId == right.objectId &&
        left.authPublicKeyBase64 == right.authPublicKeyBase64;
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class _StoredChallenge {
  const _StoredChallenge({required this.object, required this.expiresAt});

  final PrivateStateObjectReference object;
  final DateTime expiresAt;
}
