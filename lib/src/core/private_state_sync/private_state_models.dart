import 'dart:typed_data';

/// Feature-level domains supported by the private-state object protocol.
///
/// These wire names are part of key derivation. Renaming one creates a new,
/// unrelated remote object namespace and therefore requires a protocol
/// migration rather than an ordinary source refactor.
enum PrivateStateNamespace {
  votingCompletion('voting-completion'),
  swapHistory('swap-history'),
  payHistory('pay-history');

  const PrivateStateNamespace(this.wireName);

  final String wireName;
}

enum PrivateStateRequestMethod {
  get('GET'),
  put('PUT'),
  delete('DELETE');

  const PrivateStateRequestMethod(this.wireName);

  final String wireName;
}

/// Local handle used to resolve an account's UFVK inside Rust.
///
/// [accountUuid] is never part of remote identity. It may differ after import
/// on another device; only the resolved UFVK, network, namespace, and item key
/// participate in deterministic object derivation.
class PrivateStateAccount {
  const PrivateStateAccount({
    required this.dbPath,
    required this.network,
    required this.accountUuid,
  });

  final String dbPath;
  final String network;
  final String accountUuid;
}

class PrivateStateObjectKey {
  const PrivateStateObjectKey({required this.namespace, required this.itemKey});

  final PrivateStateNamespace namespace;
  final String itemKey;
}

class PrivateStateObjectReference {
  const PrivateStateObjectReference({
    required this.protocolVersion,
    required this.objectId,
    required this.authPublicKeyBase64,
  });

  final int protocolVersion;
  final String objectId;
  final String authPublicKeyBase64;
}

class PrivateStateEnvelope {
  const PrivateStateEnvelope({
    required this.protocolVersion,
    required this.objectId,
    required this.authPublicKeyBase64,
    required this.revision,
    required this.previousHashBase64,
    required this.nonceBase64,
    required this.ciphertextBase64,
    required this.signatureBase64,
    required this.envelopeHashBase64,
  });

  final int protocolVersion;
  final String objectId;
  final String authPublicKeyBase64;
  final BigInt revision;
  final String? previousHashBase64;
  final String nonceBase64;
  final String ciphertextBase64;
  final String signatureBase64;
  final String envelopeHashBase64;

  PrivateStateVersion get version => PrivateStateVersion(
    revision: revision,
    envelopeHashBase64: envelopeHashBase64,
  );
}

class PrivateStateVersion {
  const PrivateStateVersion({
    required this.revision,
    required this.envelopeHashBase64,
  });

  final BigInt revision;
  final String envelopeHashBase64;
}

class PrivateStateRequestAuthorization {
  const PrivateStateRequestAuthorization({
    required this.protocolVersion,
    required this.objectId,
    required this.authPublicKeyBase64,
    required this.method,
    required this.challengeBase64,
    required this.audience,
    required this.expiresAt,
    required this.contentHashBase64,
    required this.signatureBase64,
  });

  final int protocolVersion;
  final String objectId;
  final String authPublicKeyBase64;
  final PrivateStateRequestMethod method;
  final String challengeBase64;
  final String audience;
  final DateTime expiresAt;
  final String contentHashBase64;
  final String signatureBase64;
}

class PrivateStateServerChallenge {
  const PrivateStateServerChallenge({
    required this.valueBase64,
    required this.expiresAt,
  });

  final String valueBase64;
  final DateTime expiresAt;
}

sealed class PrivateStateRemoteReadResult {
  const PrivateStateRemoteReadResult();
}

class PrivateStateRemoteAbsent extends PrivateStateRemoteReadResult {
  const PrivateStateRemoteAbsent();
}

class PrivateStateRemoteFound extends PrivateStateRemoteReadResult {
  const PrivateStateRemoteFound(this.envelope);

  final PrivateStateEnvelope envelope;
}

sealed class PrivateStateRemotePutResult {
  const PrivateStateRemotePutResult();
}

class PrivateStateRemoteStored extends PrivateStateRemotePutResult {
  const PrivateStateRemoteStored();
}

/// The server's CAS precondition did not match.
///
/// No automatic winner or merge is selected at this layer. The feature
/// adapter must perform an authenticated read and apply its own state rules.
class PrivateStateRemoteConflict extends PrivateStateRemotePutResult {
  const PrivateStateRemoteConflict();
}

sealed class PrivateStateReadResult {
  const PrivateStateReadResult();
}

class PrivateStateReadAbsent extends PrivateStateReadResult {
  const PrivateStateReadAbsent();
}

class PrivateStateReadFound extends PrivateStateReadResult {
  const PrivateStateReadFound({required this.plaintext, required this.version});

  final Uint8List plaintext;
  final PrivateStateVersion version;
}

sealed class PrivateStateWriteResult {
  const PrivateStateWriteResult();
}

class PrivateStateWriteStored extends PrivateStateWriteResult {
  const PrivateStateWriteStored(this.version);

  final PrivateStateVersion version;
}

class PrivateStateWriteConflict extends PrivateStateWriteResult {
  const PrivateStateWriteConflict();
}

class PrivateStateProtocolException implements Exception {
  const PrivateStateProtocolException(this.message);

  final String message;

  @override
  String toString() => 'PrivateStateProtocolException: $message';
}
