import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'private_state_crypto.dart';
import 'private_state_models.dart';
import 'private_state_remote_store.dart';

abstract interface class PrivateStateObjectRepository {
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  });

  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  });
}

/// Coordinates deterministic object lookup, request authentication, remote
/// create-once storage, and authenticated decryption without applying
/// feature-specific conflict policy.
class DefaultPrivateStateObjectRepository
    implements PrivateStateObjectRepository {
  static const maxAuthorizationLifetime = Duration(minutes: 2);
  static const authorizationLifetime = Duration(minutes: 1);
  static const _emptyContentHashBase64 =
      '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU';

  DefaultPrivateStateObjectRepository({
    required PrivateStateCrypto crypto,
    required PrivateStateRemoteStore remote,
    DateTime Function()? now,
  }) : _crypto = crypto,
       _remote = remote,
       _now = now ?? DateTime.now;

  final PrivateStateCrypto _crypto;
  final PrivateStateRemoteStore _remote;
  final DateTime Function() _now;
  Duration _serverClockOffset = Duration.zero;

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    final object = await _crypto.deriveObjectReference(
      account: account,
      key: key,
    );
    final result = await _withClockSkewRetry(
      authorizeAndSend: () async {
        final authorization = await _authorization(
          account: account,
          key: key,
          object: object,
          method: PrivateStateRequestMethod.get,
        );
        return _remote.get(object: object, authorization: authorization);
      },
    );
    debugPrint(
      '[private-state] read ${result is PrivateStateRemoteFound ? 'found' : 'absent'} '
      'namespace=${key.namespace.wireName}',
    );
    return switch (result) {
      PrivateStateRemoteAbsent() => const PrivateStateReadAbsent(),
      PrivateStateRemoteFound(:final envelope) => PrivateStateReadFound(
        plaintext: await _crypto.open(
          account: account,
          key: key,
          envelope: envelope,
        ),
      ),
    };
  }

  @override
  Future<PrivateStateCreateResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) async {
    final object = await _crypto.deriveObjectReference(
      account: account,
      key: key,
    );
    final envelope = await _crypto.seal(
      account: account,
      key: key,
      plaintext: plaintext,
    );
    _requireEnvelopeMatchesObject(envelope, object);
    final result = await _withClockSkewRetry(
      authorizeAndSend: () async {
        final authorization = await _authorization(
          account: account,
          key: key,
          object: object,
          method: PrivateStateRequestMethod.put,
          envelope: envelope,
        );
        return _remote.create(
          object: object,
          envelope: envelope,
          authorization: authorization,
        );
      },
    );
    debugPrint(
      '[private-state] create '
      '${result is PrivateStateRemoteCreated ? 'success' : 'conflict'} '
      'namespace=${key.namespace.wireName}',
    );
    return switch (result) {
      PrivateStateRemoteCreated() => const PrivateStateCreated(),
      PrivateStateRemoteConflict() => const PrivateStateCreateConflict(),
    };
  }

  Future<PrivateStateRequestAuthorization> _authorization({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateObjectReference object,
    required PrivateStateRequestMethod method,
    PrivateStateEnvelope? envelope,
  }) async {
    final serverAdjustedNow = _now().toUtc().add(_serverClockOffset);
    final clientExpiry = serverAdjustedNow.add(authorizationLifetime);
    final normalizedExpiry = DateTime.fromMillisecondsSinceEpoch(
      clientExpiry.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
    final audience = _remote.audience;
    final authorization = await _crypto.authorize(
      account: account,
      key: key,
      method: method,
      audience: audience,
      expiresAt: normalizedExpiry,
      envelope: envelope,
    );
    if (authorization.protocolVersion != object.protocolVersion ||
        authorization.objectId != object.objectId ||
        authorization.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        authorization.method != method ||
        authorization.audience != audience ||
        authorization.expiresAt.toUtc() != normalizedExpiry ||
        (envelope == null &&
            authorization.contentHashBase64 != _emptyContentHashBase64)) {
      throw const PrivateStateProtocolException(
        'Request authorization does not match the requested object.',
      );
    }
    return authorization;
  }

  Future<T> _withClockSkewRetry<T>({
    required Future<T> Function() authorizeAndSend,
  }) async {
    try {
      return await authorizeAndSend();
    } on PrivateStateClockSkewException catch (error) {
      _serverClockOffset = error.serverTime.toUtc().difference(_now().toUtc());
      return authorizeAndSend();
    }
  }

  void _requireEnvelopeMatchesObject(
    PrivateStateEnvelope envelope,
    PrivateStateObjectReference object,
  ) {
    if (envelope.objectId != object.objectId ||
        envelope.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        envelope.protocolVersion != object.protocolVersion) {
      throw const PrivateStateProtocolException(
        'Sealed envelope does not match the requested object.',
      );
    }
  }
}
