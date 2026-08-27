import '../../rust/api/private_state_sync.dart' as rust;
import 'private_state_crypto.dart';
import 'private_state_models.dart';

/// Public-key-only verification boundary used by an opaque storage server.
abstract interface class PrivateStateServerVerifier {
  Future<void> verifyObjectReference(PrivateStateObjectReference object);

  Future<void> verifyAuthorization(
    PrivateStateRequestAuthorization authorization,
  );

  Future<void> verifyPutContent({
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  });
}

class RustPrivateStateServerVerifier implements PrivateStateServerVerifier {
  const RustPrivateStateServerVerifier();

  @override
  Future<void> verifyObjectReference(PrivateStateObjectReference object) {
    return rust.verifyPrivateStateObjectReference(
      reference: rust.ApiPrivateStateObjectReference(
        protocolVersion: object.protocolVersion,
        objectId: object.objectId,
        authPublicKeyBase64: object.authPublicKeyBase64,
      ),
    );
  }

  @override
  Future<void> verifyAuthorization(
    PrivateStateRequestAuthorization authorization,
  ) {
    return rust.verifyPrivateStateRequestAuthorization(
      authorization: privateStateAuthorizationToRust(authorization),
    );
  }

  @override
  Future<void> verifyPutContent({
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  }) {
    return rust.verifyPrivateStatePutAuthorizationContent(
      envelope: privateStateEnvelopeToRust(envelope),
      authorization: privateStateAuthorizationToRust(authorization),
    );
  }
}

rust.ApiPrivateStateRequestAuthorization privateStateAuthorizationToRust(
  PrivateStateRequestAuthorization authorization,
) {
  return rust.ApiPrivateStateRequestAuthorization(
    protocolVersion: authorization.protocolVersion,
    objectId: authorization.objectId,
    authPublicKeyBase64: authorization.authPublicKeyBase64,
    method: authorization.method.wireName,
    challengeBase64: authorization.challengeBase64,
    audience: authorization.audience,
    expiresAtSeconds: BigInt.from(
      authorization.expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    ),
    contentHashBase64: authorization.contentHashBase64,
    signatureBase64: authorization.signatureBase64,
  );
}
