import 'dart:typed_data';

import '../../rust/api/private_state_sync.dart' as rust;
import 'private_state_models.dart';

/// Cryptographic boundary for private-state objects.
///
/// Implementations must keep the UFVK and all derived secret keys inside the
/// wallet cryptography layer. Dart receives only public references, opaque
/// envelopes, request authorizations, and authenticated plaintext.
abstract interface class PrivateStateCrypto {
  Future<PrivateStateObjectReference> deriveObjectReference({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  });

  Future<PrivateStateEnvelope> seal({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required BigInt revision,
    required String? previousHashBase64,
    required Uint8List plaintext,
  });

  Future<Uint8List> open({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateEnvelope envelope,
  });

  Future<PrivateStateRequestAuthorization> authorize({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateRequestMethod method,
    required PrivateStateServerChallenge challenge,
    required String audience,
    String? contentHashBase64,
  });
}

class RustPrivateStateCrypto implements PrivateStateCrypto {
  const RustPrivateStateCrypto();

  @override
  Future<PrivateStateObjectReference> deriveObjectReference({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
  }) async {
    final reference = await rust.derivePrivateStateObjectReference(
      dbPath: account.dbPath,
      network: account.network,
      accountUuid: account.accountUuid,
      namespace: key.namespace.wireName,
      itemKey: key.itemKey,
    );
    return PrivateStateObjectReference(
      protocolVersion: reference.protocolVersion,
      objectId: reference.objectId,
      authPublicKeyBase64: reference.authPublicKeyBase64,
    );
  }

  @override
  Future<PrivateStateEnvelope> seal({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required BigInt revision,
    required String? previousHashBase64,
    required Uint8List plaintext,
  }) async {
    final envelope = await rust.sealPrivateStateObject(
      dbPath: account.dbPath,
      network: account.network,
      accountUuid: account.accountUuid,
      namespace: key.namespace.wireName,
      itemKey: key.itemKey,
      revision: revision,
      previousHashBase64: previousHashBase64,
      plaintext: plaintext,
    );
    return _envelopeFromRust(envelope);
  }

  @override
  Future<Uint8List> open({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateEnvelope envelope,
  }) {
    return rust.openPrivateStateObject(
      dbPath: account.dbPath,
      network: account.network,
      accountUuid: account.accountUuid,
      namespace: key.namespace.wireName,
      itemKey: key.itemKey,
      envelope: _envelopeToRust(envelope),
    );
  }

  @override
  Future<PrivateStateRequestAuthorization> authorize({
    required PrivateStateAccount account,
    required PrivateStateObjectKey key,
    required PrivateStateRequestMethod method,
    required PrivateStateServerChallenge challenge,
    required String audience,
    String? contentHashBase64,
  }) async {
    final authorization = await rust.authorizePrivateStateRequest(
      dbPath: account.dbPath,
      network: account.network,
      accountUuid: account.accountUuid,
      namespace: key.namespace.wireName,
      itemKey: key.itemKey,
      method: method.wireName,
      challengeBase64: challenge.valueBase64,
      audience: audience,
      expiresAtSeconds: BigInt.from(
        challenge.expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      ),
      contentHashBase64: contentHashBase64,
    );
    return PrivateStateRequestAuthorization(
      protocolVersion: authorization.protocolVersion,
      objectId: authorization.objectId,
      authPublicKeyBase64: authorization.authPublicKeyBase64,
      method: method,
      challengeBase64: authorization.challengeBase64,
      audience: authorization.audience,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        authorization.expiresAtSeconds.toInt() * 1000,
        isUtc: true,
      ),
      contentHashBase64: authorization.contentHashBase64,
      signatureBase64: authorization.signatureBase64,
    );
  }
}

PrivateStateEnvelope _envelopeFromRust(rust.ApiPrivateStateEnvelope envelope) {
  return PrivateStateEnvelope(
    protocolVersion: envelope.protocolVersion,
    objectId: envelope.objectId,
    authPublicKeyBase64: envelope.authPublicKeyBase64,
    revision: envelope.revision,
    previousHashBase64: envelope.previousHashBase64,
    nonceBase64: envelope.nonceBase64,
    ciphertextBase64: envelope.ciphertextBase64,
    signatureBase64: envelope.signatureBase64,
    envelopeHashBase64: envelope.envelopeHashBase64,
  );
}

rust.ApiPrivateStateEnvelope _envelopeToRust(PrivateStateEnvelope envelope) {
  return rust.ApiPrivateStateEnvelope(
    protocolVersion: envelope.protocolVersion,
    objectId: envelope.objectId,
    authPublicKeyBase64: envelope.authPublicKeyBase64,
    revision: envelope.revision,
    previousHashBase64: envelope.previousHashBase64,
    nonceBase64: envelope.nonceBase64,
    ciphertextBase64: envelope.ciphertextBase64,
    signatureBase64: envelope.signatureBase64,
    envelopeHashBase64: envelope.envelopeHashBase64,
  );
}
