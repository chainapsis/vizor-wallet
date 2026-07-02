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

  Future<rust_multisig.ApiPreparedMultisigSigningRequest>
  prepareSigningRequest({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String requestSeed,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required bool needsSaplingParams,
    required String amountZatoshi,
    required String feeZatoshi,
    required String recipientAddress,
    String? memo,
  });

  Future<rust_multisig.ApiMultisigSigningRequest> submitPreparedSigningRequest({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required String pcztHash,
    required String requestJson,
    required String idempotencyKey,
  });

  Future<rust_multisig.ApiMultisigSigningInbox> getSigningInbox({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required int after,
  });

  Future<rust_multisig.ApiMultisigSessionEvents> getSessionEvents({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required int after,
  });

  Future<rust_multisig.ApiMultisigSigningAdvance> submitSigningRound1({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String keyPackageB64,
    String? localStateJson,
  });

  Future<rust_multisig.ApiMultisigSigningAdvance> submitSigningRound2({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String keyPackageB64,
    String? localStateJson,
  });

  Future<rust_multisig.ApiMultisigSignedPczt> aggregateSignedPczt({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String groupPublicPackageJson,
    String? localStateJson,
  });

  Future<rust_multisig.ApiMultisigSigningAdvance> postBroadcastResult({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required List<String> selectedParticipantIds,
    required String pcztHash,
    required String txid,
    String? localStateJson,
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

  @override
  Future<rust_multisig.ApiPreparedMultisigSigningRequest>
  prepareSigningRequest({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String requestSeed,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required bool needsSaplingParams,
    required String amountZatoshi,
    required String feeZatoshi,
    required String recipientAddress,
    String? memo,
  }) {
    return rust_multisig.prepareMultisigSigningRequest(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      participantId: participantId,
      accessToken: accessToken,
      rosterHash: rosterHash,
      requestSeed: requestSeed,
      selectedParticipantIds: selectedParticipantIds,
      pcztBytes: pcztBytes,
      needsSaplingParams: needsSaplingParams,
      amountZatoshi: amountZatoshi,
      feeZatoshi: feeZatoshi,
      recipientAddress: recipientAddress,
      memo: memo,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningRequest> submitPreparedSigningRequest({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required String pcztHash,
    required String requestJson,
    required String idempotencyKey,
  }) {
    return rust_multisig.submitPreparedMultisigSigningRequest(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      accessToken: accessToken,
      pcztHash: pcztHash,
      requestJson: requestJson,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningInbox> getSigningInbox({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required int after,
  }) {
    return rust_multisig.getMultisigSigningInbox(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      participantId: participantId,
      accessToken: accessToken,
      rosterHash: rosterHash,
      deliverySecretKey: deliverySecretKey,
      after: after,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSessionEvents> getSessionEvents({
    required String coordinatorUrl,
    required String sessionId,
    required String accessToken,
    required int after,
  }) {
    return rust_multisig.getMultisigSessionEvents(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      accessToken: accessToken,
      after: after,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningAdvance> submitSigningRound1({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String keyPackageB64,
    String? localStateJson,
  }) {
    return rust_multisig.submitMultisigSigningRound1(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      signingRequestId: signingRequestId,
      participantId: participantId,
      accessToken: accessToken,
      rosterHash: rosterHash,
      selectedParticipantIds: selectedParticipantIds,
      pcztBytes: pcztBytes,
      keyPackageB64: keyPackageB64,
      localStateJson: localStateJson,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningAdvance> submitSigningRound2({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String keyPackageB64,
    String? localStateJson,
  }) {
    return rust_multisig.submitMultisigSigningRound2(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      signingRequestId: signingRequestId,
      participantId: participantId,
      accessToken: accessToken,
      rosterHash: rosterHash,
      deliverySecretKey: deliverySecretKey,
      selectedParticipantIds: selectedParticipantIds,
      pcztBytes: pcztBytes,
      keyPackageB64: keyPackageB64,
      localStateJson: localStateJson,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSignedPczt> aggregateSignedPczt({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required String deliverySecretKey,
    required List<String> selectedParticipantIds,
    required List<int> pcztBytes,
    required String groupPublicPackageJson,
    String? localStateJson,
  }) {
    return rust_multisig.aggregateMultisigSignedPczt(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      signingRequestId: signingRequestId,
      participantId: participantId,
      accessToken: accessToken,
      rosterHash: rosterHash,
      deliverySecretKey: deliverySecretKey,
      selectedParticipantIds: selectedParticipantIds,
      pcztBytes: pcztBytes,
      groupPublicPackageJson: groupPublicPackageJson,
      localStateJson: localStateJson,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningAdvance> postBroadcastResult({
    required String coordinatorUrl,
    required String sessionId,
    required String signingRequestId,
    required String participantId,
    required String accessToken,
    required String rosterHash,
    required List<String> selectedParticipantIds,
    required String pcztHash,
    required String txid,
    String? localStateJson,
  }) {
    return rust_multisig.postMultisigBroadcastResult(
      coordinatorUrl: coordinatorUrl,
      sessionId: sessionId,
      signingRequestId: signingRequestId,
      participantId: participantId,
      accessToken: accessToken,
      rosterHash: rosterHash,
      selectedParticipantIds: selectedParticipantIds,
      pcztHash: pcztHash,
      txid: txid,
      localStateJson: localStateJson,
    );
  }
}

final multisigCoordinatorServiceProvider = Provider<MultisigCoordinatorService>(
  (ref) => const RustMultisigCoordinatorService(),
);

/// Coordinator refresh tokens are single-use (the server rotates them), so
/// concurrent refreshes for the same participant race each other: the loser
/// falls back to the admission-resume path and can clobber the winner's fresh
/// token pair in storage. This shares one in-flight refresh per participant.
class MultisigAuthRefresher {
  MultisigAuthRefresher(this._ref);

  final Ref _ref;
  final Map<String, Future<rust_multisig.ApiMultisigAuthUpdate>> _inFlight = {};

  Future<rust_multisig.ApiMultisigAuthUpdate> refreshOrResume({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String refreshToken,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) {
    final key = '$coordinatorUrl|$sessionId|$participantId';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    late final Future<rust_multisig.ApiMultisigAuthUpdate> refresh;
    refresh =
        _ref
            .read(multisigCoordinatorServiceProvider)
            .refreshOrResumeAuth(
              coordinatorUrl: coordinatorUrl,
              sessionId: sessionId,
              participantId: participantId,
              refreshToken: refreshToken,
              admissionSecretKey: admissionSecretKey,
              deliverySecretKey: deliverySecretKey,
            )
            .whenComplete(() {
              if (identical(_inFlight[key], refresh)) {
                _inFlight.remove(key);
              }
            });
    _inFlight[key] = refresh;
    return refresh;
  }
}

final multisigAuthRefresherProvider = Provider<MultisigAuthRefresher>(
  MultisigAuthRefresher.new,
);
