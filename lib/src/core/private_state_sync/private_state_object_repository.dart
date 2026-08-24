import 'dart:typed_data';

import 'private_state_crypto.dart';
import 'private_state_models.dart';
import 'private_state_remote_store.dart';

abstract interface class PrivateStateObjectRepository {
  Future<PrivateStateReadResult> read({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  });

  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  });

  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  });
}

/// Coordinates deterministic object lookup, request authentication, remote
/// CAS, and authenticated decryption without applying feature-specific merge
/// policy.
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
        version: envelope.version,
      ),
    };
  }

  @override
  Future<PrivateStateWriteResult> create({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required Uint8List plaintext,
  }) {
    return _write(
      account: account,
      key: key,
      revision: BigInt.one,
      previousHashBase64: null,
      expectedVersion: null,
      plaintext: plaintext,
    );
  }

  @override
  Future<PrivateStateWriteResult> compareAndSet({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateVersion currentVersion,
    required Uint8List plaintext,
  }) {
    if (currentVersion.revision < BigInt.one ||
        currentVersion.envelopeHashBase64.isEmpty) {
      throw const PrivateStateProtocolException(
        'CAS requires a positive revision and authenticated envelope hash.',
      );
    }
    return _write(
      account: account,
      key: key,
      revision: currentVersion.revision + BigInt.one,
      previousHashBase64: currentVersion.envelopeHashBase64,
      expectedVersion: currentVersion,
      plaintext: plaintext,
    );
  }

  Future<PrivateStateWriteResult> _write({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required BigInt revision,
    required String? previousHashBase64,
    required PrivateStateVersion? expectedVersion,
    required Uint8List plaintext,
  }) async {
    final object = await _crypto.deriveObjectReference(
      account: account,
      key: key,
    );
    final envelope = await _crypto.seal(
      account: account,
      key: key,
      revision: revision,
      previousHashBase64: previousHashBase64,
      plaintext: plaintext,
    );
    _requireEnvelopeMatchesObject(envelope, object);
    final authorization = await _authorization(
      account: account,
      key: key,
      object: object,
      method: PrivateStateRequestMethod.put,
      contentHashBase64: envelope.envelopeHashBase64,
    );
    final result = await _remote.put(
      object: object,
      envelope: envelope,
      authorization: authorization,
      expectedVersion: expectedVersion,
    );
    return switch (result) {
      PrivateStateRemoteStored() => PrivateStateWriteStored(envelope.version),
      PrivateStateRemoteConflict() => const PrivateStateWriteConflict(),
    };
  }

  Future<PrivateStateRequestAuthorization> _authorization({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateObjectReference object,
    required PrivateStateRequestMethod method,
    String? contentHashBase64,
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
      contentHashBase64: contentHashBase64,
    );
    final expectedContentHash = contentHashBase64 ?? _emptyContentHashBase64;
    if (authorization.protocolVersion != object.protocolVersion ||
        authorization.objectId != object.objectId ||
        authorization.authPublicKeyBase64 != object.authPublicKeyBase64 ||
        authorization.method != method ||
        authorization.challengeBase64 != challenge.valueBase64 ||
        authorization.audience != audience ||
        authorization.expiresAt.toUtc() != challenge.expiresAt ||
        authorization.contentHashBase64 != expectedContentHash) {
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
