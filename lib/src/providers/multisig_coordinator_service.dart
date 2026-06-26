import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/api/multisig.dart' as rust_multisig;

abstract class MultisigCoordinatorService {
  rust_multisig.ApiMultisigParticipantIdentity generateParticipantIdentity();

  Future<rust_multisig.ApiMultisigAuthSession> createSession({
    required String coordinatorUrl,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  });

  Future<rust_multisig.ApiMultisigAuthSession> joinSession({
    required String coordinatorUrl,
    required String sessionId,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  });

  Future<rust_multisig.ApiMultisigAuthUpdate> refreshOrResumeAuth({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String refreshToken,
    required String admissionSecretKey,
    required String deliverySecretKey,
  });

  Future<rust_multisig.ApiMultisigAuthSession> resumeParticipant({
    required String coordinatorUrl,
    required String sessionId,
    required String admissionSecretKey,
    required String deliverySecretKey,
  });

  Future<rust_multisig.ApiMultisigSession> getSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
  });

  Future<rust_multisig.ApiMultisigSession> lockSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required int threshold,
  });
}

class RustMultisigCoordinatorService implements MultisigCoordinatorService {
  const RustMultisigCoordinatorService();

  @override
  rust_multisig.ApiMultisigParticipantIdentity generateParticipantIdentity() {
    return rust_multisig.generateMultisigParticipantIdentity();
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> createSession({
    required String coordinatorUrl,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  }) {
    return rust_multisig.createMultisigSession(
      coordinatorUrl: coordinatorUrl,
      admissionSecretKey: identity.admissionSecretKey,
      deliverySecretKey: identity.deliverySecretKey,
      label: label,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> joinSession({
    required String coordinatorUrl,
    required String sessionId,
    required rust_multisig.ApiMultisigParticipantIdentity identity,
    String? label,
  }) {
    return rust_multisig.joinMultisigSession(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      admissionSecretKey: identity.admissionSecretKey,
      deliverySecretKey: identity.deliverySecretKey,
      label: label,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigAuthUpdate> refreshOrResumeAuth({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String refreshToken,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) {
    return rust_multisig.refreshOrResumeMultisigAuth(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      participantId: participantId,
      refreshToken: refreshToken,
      admissionSecretKey: admissionSecretKey,
      deliverySecretKey: deliverySecretKey,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigAuthSession> resumeParticipant({
    required String coordinatorUrl,
    required String sessionId,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) {
    return rust_multisig.resumeMultisigParticipant(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      admissionSecretKey: admissionSecretKey,
      deliverySecretKey: deliverySecretKey,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSession> getSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
  }) {
    return rust_multisig.getMultisigSession(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      accessToken: accessToken,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSession> lockSession({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required int threshold,
  }) {
    return rust_multisig.lockMultisigSession(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      accessToken: accessToken,
      threshold: threshold,
    );
  }
}

final multisigCoordinatorServiceProvider = Provider<MultisigCoordinatorService>(
  (ref) => const RustMultisigCoordinatorService(),
);
