import 'dart:async';

import 'private_state_models.dart';
import 'private_state_remote_store.dart';
import 'private_state_server_verifier.dart';

/// Executable reference for the opaque server contract.
///
/// This implementation is intentionally process-local and is not selected by
/// production providers. It models request nonce single-use, signature,
/// expiry, and atomic create-once requirements that an HTTP service preserves.
class InMemoryPrivateStateRemoteStore implements PrivateStateRemoteStore {
  InMemoryPrivateStateRemoteStore({
    required this.audience,
    required PrivateStateServerVerifier verifier,
    DateTime Function()? now,
    this.maximumAuthorizationLifetime = const Duration(minutes: 2),
    this.nonceRetention = const Duration(minutes: 2),
    this.maxRetainedNonces = 1024,
  }) : _verifier = verifier,
       _now = now ?? DateTime.now {
    if (maximumAuthorizationLifetime < const Duration(seconds: 1)) {
      throw ArgumentError.value(
        maximumAuthorizationLifetime,
        'maximumAuthorizationLifetime',
        'Must be at least one second.',
      );
    }
    if (nonceRetention < maximumAuthorizationLifetime) {
      throw ArgumentError.value(
        nonceRetention,
        'nonceRetention',
        'Must cover the maximum authorization lifetime.',
      );
    }
    if (maxRetainedNonces <= 0) {
      throw ArgumentError.value(
        maxRetainedNonces,
        'maxRetainedNonces',
        'Must be positive.',
      );
    }
  }

  @override
  final String audience;
  final PrivateStateServerVerifier _verifier;
  final DateTime Function() _now;
  final Duration maximumAuthorizationLifetime;
  final Duration nonceRetention;
  final int maxRetainedNonces;

  final Map<String, DateTime> _usedNonces = {};
  final Map<String, PrivateStateEnvelope> _objects = {};
  Future<void> _operationTail = Future.value();

  @override
  Future<PrivateStateRemoteReadResult> get({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
  }) {
    return _exclusive(() async {
      await _verifyAndClaim(
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
  Future<PrivateStateRemoteCreateResult> create({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  }) {
    return _exclusive(() async {
      await _verifyAndClaim(
        object: object,
        authorization: authorization,
        method: PrivateStateRequestMethod.put,
        envelope: envelope,
      );
      if (_objects.containsKey(object.objectId)) {
        return const PrivateStateRemoteConflict();
      }
      _objects[object.objectId] = envelope;
      return const PrivateStateRemoteCreated();
    });
  }

  Future<void> _verifyAndClaim({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
    required PrivateStateRequestMethod method,
    PrivateStateEnvelope? envelope,
  }) async {
    final now = _now().toUtc();
    await _verifier.verifyObjectReference(object);
    if (authorization.protocolVersion != object.protocolVersion ||
        authorization.objectId != object.objectId ||
        authorization.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        authorization.method != method ||
        authorization.audience != audience) {
      throw const PrivateStateProtocolException(
        'Authorization does not match the request.',
      );
    }
    await _verifier.verifyAuthorization(authorization);
    if (envelope != null) {
      await _verifier.verifyPutContent(
        envelope: envelope,
        authorization: authorization,
      );
    }
    final expiresAt = authorization.expiresAt.toUtc();
    if (!expiresAt.isAfter(now) ||
        expiresAt.isAfter(now.add(maximumAuthorizationLifetime))) {
      throw PrivateStateClockSkewException(now);
    }
    _usedNonces.removeWhere((_, retainedUntil) => !retainedUntil.isAfter(now));
    if (_usedNonces.containsKey(authorization.nonceBase64)) {
      throw const PrivateStateProtocolException(
        'Request nonce has already been used.',
      );
    }
    if (_usedNonces.length >= maxRetainedNonces) {
      throw const PrivateStateProtocolException(
        'Reference store nonce capacity exceeded.',
      );
    }
    _usedNonces[authorization.nonceBase64] = now.add(nonceRetention);
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
