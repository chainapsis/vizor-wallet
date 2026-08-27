import 'private_state_models.dart';

/// Untrusted opaque-object transport.
///
/// A production implementation may use HTTP, but this contract contains no
/// HTTP concerns. The server is responsible for challenge freshness,
/// authorization signature verification, create-once atomicity, size limits,
/// and rate limits.
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

  /// Atomically creates [envelope]. An existing object is never replaced.
  Future<PrivateStateRemoteCreateResult> create({
    required PrivateStateObjectReference object,
    required PrivateStateEnvelope envelope,
    required PrivateStateRequestAuthorization authorization,
  });
}
