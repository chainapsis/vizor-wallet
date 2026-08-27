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
  put('PUT');

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
    required this.nonceBase64,
    required this.ciphertextBase64,
    required this.signatureBase64,
  });

  final int protocolVersion;
  final String objectId;
  final String authPublicKeyBase64;
  final String nonceBase64;
  final String ciphertextBase64;
  final String signatureBase64;
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

sealed class PrivateStateRemoteCreateResult {
  const PrivateStateRemoteCreateResult();
}

class PrivateStateRemoteCreated extends PrivateStateRemoteCreateResult {
  const PrivateStateRemoteCreated();
}

/// An immutable object already exists for this derived key.
class PrivateStateRemoteConflict extends PrivateStateRemoteCreateResult {
  const PrivateStateRemoteConflict();
}

sealed class PrivateStateReadResult {
  const PrivateStateReadResult();
}

class PrivateStateReadAbsent extends PrivateStateReadResult {
  const PrivateStateReadAbsent();
}

class PrivateStateReadFound extends PrivateStateReadResult {
  const PrivateStateReadFound({required this.plaintext});

  final Uint8List plaintext;
}

sealed class PrivateStateCreateResult {
  const PrivateStateCreateResult();
}

class PrivateStateCreated extends PrivateStateCreateResult {
  const PrivateStateCreated();
}

class PrivateStateCreateConflict extends PrivateStateCreateResult {
  const PrivateStateCreateConflict();
}

class PrivateStateProtocolException implements Exception {
  const PrivateStateProtocolException(this.message);

  final String message;

  @override
  String toString() => 'PrivateStateProtocolException: $message';
}
