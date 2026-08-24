import 'private_state_models.dart';

/// Untrusted opaque-object transport.
///
/// A production implementation may use HTTP, but this contract contains no
/// HTTP concerns. The server is responsible for challenge freshness,
/// authorization signature verification, CAS, size limits, and rate limits.
/// It never receives a UFVK or plaintext.
abstract interface class PrivateStateRemoteStore {
  /// Stable signature audience for this server/protocol deployment.
  String get audience;

  Future<PrivateStateServerChallenge> createChallenge({
    required PrivateStateObjectReference object,
  });

  Future<PrivateStateRemoteReadResult> get({
    required PrivateStateObjectReference object,
    required PrivateStateRequestAuthorization authorization,
  });

  /// Stores [envelope] only when the remote revision and authenticated
  /// envelope hash both match [expectedVersion]. The server must additionally
  /// verify that [envelope] is the direct hash-chain successor of that stored
  /// version; [expectedVersion] is transport metadata and is not signed. A null
  /// expected version means create-if-absent at revision 1.
  Future<PrivateStateRemotePutResult> put({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
    required PrivateStateVersion? expectedVersion,
  });
}
