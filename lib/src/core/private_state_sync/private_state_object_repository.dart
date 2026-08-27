import 'dart:typed_data';

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
  static const _emptyContentHashBase64 =
      '47DEQpj8HBSa-_TImW-5JCeuQeRkm5NMpJWZG3hSuFU';

  const DefaultPrivateStateObjectRepository({
    required PrivateStateCrypto crypto,
    required PrivateStateRemoteStore remote,
    DateTime Function()? now,
  }) : _crypto = crypto,
       _remote = remote,
       _now = now ?? DateTime.now;

  final PrivateStateCrypto _crypto;
  final PrivateStateRemoteStore _remote;
  final DateTime Function() _now;

  @override
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    final object = await _crypto.deriveObjectReference(
      account: account,
      key: key,
    );
    final authorization = await _authorization(
      account: account,
      key: key,
      object: object,
      method: PrivateStateRequestMethod.get,
    );
    final result = await _remote.get(
      object: object,
      authorization: authorization,
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
    final authorization = await _authorization(
      account: account,
      key: key,
      object: object,
      method: PrivateStateRequestMethod.put,
      envelope: envelope,
    );
    final result = await _remote.create(
      object: object,
      envelope: envelope,
      authorization: authorization,
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
    final serverChallenge = await _remote.createChallenge(object: object);
    final now = _now().toUtc();
    final serverExpiry = serverChallenge.expiresAt.toUtc();
    if (!serverExpiry.isAfter(now)) {
      throw const PrivateStateProtocolException(
        'Remote store returned an expired challenge.',
      );
    }
    // The server may accept a shorter authorization than the challenge's own
    // lifetime. Never let it make a captured signature replayable beyond the
    // client's short request window.
    final clientExpiry = now.add(maxAuthorizationLifetime);
    final selectedExpiry = serverExpiry.isBefore(clientExpiry)
        ? serverExpiry
        : clientExpiry;
    final normalizedExpiry = DateTime.fromMillisecondsSinceEpoch(
      selectedExpiry.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
    if (!normalizedExpiry.isAfter(now)) {
      throw const PrivateStateProtocolException(
        'Remote challenge lifetime is too short to authorize safely.',
      );
    }
    final challenge = PrivateStateServerChallenge(
      valueBase64: serverChallenge.valueBase64,
      expiresAt: normalizedExpiry,
    );
    final audience = _remote.audience;
    final authorization = await _crypto.authorize(
      account: account,
      key: key,
      method: method,
      challenge: challenge,
      audience: audience,
      envelope: envelope,
    );
    if (authorization.protocolVersion != object.protocolVersion ||
        authorization.objectId != object.objectId ||
        authorization.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        authorization.method != method ||
        authorization.challengeBase64 != challenge.valueBase64 ||
        authorization.audience != audience ||
        authorization.expiresAt.toUtc() != challenge.expiresAt ||
        (envelope == null &&
            authorization.contentHashBase64 != _emptyContentHashBase64)) {
      throw const PrivateStateProtocolException(
        'Request authorization does not match the requested object.',
      );
    }
    return authorization;
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
