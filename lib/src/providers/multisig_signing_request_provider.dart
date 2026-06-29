import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_secure_store.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/multisig.dart' as rust_multisig;
import '../rust/api/sync.dart' as rust_sync;
import 'app_security_provider.dart';
import 'multisig_account_material_provider.dart';
import 'multisig_coordinator_service.dart';
import 'multisig_operation_error.dart';
import 'multisig_pending_session_provider.dart';
import 'rpc_endpoint_failover_provider.dart';
import 'rpc_endpoint_provider.dart';
import 'sync_provider.dart';

const kMultisigSigningRequestsStorageKey = 'zcash_multisig_signing_requests_v1';
const multisigSigningDraftState = 'draft';
const _accessTokenRefreshSkewSeconds = 30;

class MultisigSigningParticipant {
  const MultisigSigningParticipant({
    required this.participantId,
    required this.deliveryPublicKey,
    required this.displayName,
  });

  final String participantId;
  final String deliveryPublicKey;
  final String displayName;

  String get shortParticipantId => _shortId(participantId);

  static MultisigSigningParticipant fromApi(
    rust_multisig.ApiMultisigParticipant value,
  ) {
    final label = value.label?.trim();
    return MultisigSigningParticipant(
      participantId: value.participantId,
      deliveryPublicKey: value.deliveryPublicKey,
      displayName: label == null || label.isEmpty
          ? _shortId(value.participantId)
          : label,
    );
  }
}

class MultisigSigningDraft {
  const MultisigSigningDraft({
    required this.material,
    required this.threshold,
    required this.participants,
  });

  final MultisigAccountMaterial material;
  final int threshold;
  final List<MultisigSigningParticipant> participants;
}

class MultisigSigningRequestRecord {
  const MultisigSigningRequestRecord({
    required this.signingRequestId,
    required this.accountUuid,
    required this.sessionId,
    required this.localParticipantId,
    required this.requesterParticipantId,
    required this.selectedParticipantIds,
    required this.pcztB64,
    required this.pcztHash,
    required this.needsSaplingParams,
    required this.amountZatoshi,
    required this.feeZatoshi,
    required this.recipientAddress,
    required this.addressType,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.sendFlowId,
    this.memo,
    this.coordinatorSubmitted = true,
    this.createRequestJson,
    this.createRequestIdempotencyKey,
    this.round1ParticipantIds = const <String>[],
    this.round2ParticipantIds = const <String>[],
    this.localStateJson,
    this.signedPcztB64,
    this.broadcastTxid,
    this.broadcastResultSent = false,
  });

  final String signingRequestId;
  final String accountUuid;
  final String sessionId;
  final String localParticipantId;
  final String requesterParticipantId;
  final List<String> selectedParticipantIds;
  final String pcztB64;
  final String pcztHash;
  final bool needsSaplingParams;
  final String amountZatoshi;
  final String feeZatoshi;
  final String recipientAddress;
  final String addressType;
  final String? memo;
  final String state;
  final int createdAt;
  final int updatedAt;
  final String? sendFlowId;
  final bool coordinatorSubmitted;
  final String? createRequestJson;
  final String? createRequestIdempotencyKey;
  final List<String> round1ParticipantIds;
  final List<String> round2ParticipantIds;
  final String? localStateJson;
  final String? signedPcztB64;
  final String? broadcastTxid;
  final bool broadcastResultSent;

  bool get isDraft => state == multisigSigningDraftState;
  bool get hasBroadcastTxid =>
      broadcastTxid != null && broadcastTxid!.isNotEmpty;
  bool get localParticipantSelected =>
      selectedParticipantIds.contains(localParticipantId);
  bool get isReviewOnly =>
      !localParticipantSelected && requesterParticipantId != localParticipantId;
  bool get isBroadcasted => hasBroadcastTxid && broadcastResultSent;
  bool get readyToBroadcast =>
      !isBroadcasted &&
      localParticipantSelected &&
      round2ParticipantIds.length >= selectedParticipantIds.length;

  String get shortSigningRequestId => _shortId(signingRequestId);

  Map<String, Object?> toJson() => {
    'signingRequestId': signingRequestId,
    'accountUuid': accountUuid,
    'sessionId': sessionId,
    'localParticipantId': localParticipantId,
    'requesterParticipantId': requesterParticipantId,
    'selectedParticipantIds': selectedParticipantIds,
    'pcztB64': pcztB64,
    'pcztHash': pcztHash,
    'needsSaplingParams': needsSaplingParams,
    'amountZatoshi': amountZatoshi,
    'feeZatoshi': feeZatoshi,
    'recipientAddress': recipientAddress,
    'addressType': addressType,
    'memo': memo,
    'state': state,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'sendFlowId': sendFlowId,
    'coordinatorSubmitted': coordinatorSubmitted,
    'createRequestJson': createRequestJson,
    'createRequestIdempotencyKey': createRequestIdempotencyKey,
    'round1ParticipantIds': round1ParticipantIds,
    'round2ParticipantIds': round2ParticipantIds,
    'localStateJson': localStateJson,
    'signedPcztB64': signedPcztB64,
    'broadcastTxid': broadcastTxid,
    'broadcastResultSent': broadcastResultSent,
  };

  MultisigSigningRequestRecord copyWith({
    String? signingRequestId,
    String? state,
    int? updatedAt,
    String? sendFlowId,
    List<String>? selectedParticipantIds,
    bool? coordinatorSubmitted,
    String? createRequestJson,
    String? createRequestIdempotencyKey,
    List<String>? round1ParticipantIds,
    List<String>? round2ParticipantIds,
    String? localStateJson,
    String? signedPcztB64,
    String? broadcastTxid,
    bool? broadcastResultSent,
  }) {
    return MultisigSigningRequestRecord(
      signingRequestId: signingRequestId ?? this.signingRequestId,
      accountUuid: accountUuid,
      sessionId: sessionId,
      localParticipantId: localParticipantId,
      requesterParticipantId: requesterParticipantId,
      selectedParticipantIds:
          selectedParticipantIds ?? this.selectedParticipantIds,
      pcztB64: pcztB64,
      pcztHash: pcztHash,
      needsSaplingParams: needsSaplingParams,
      amountZatoshi: amountZatoshi,
      feeZatoshi: feeZatoshi,
      recipientAddress: recipientAddress,
      addressType: addressType,
      memo: memo,
      state: state ?? this.state,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sendFlowId: sendFlowId ?? this.sendFlowId,
      coordinatorSubmitted: coordinatorSubmitted ?? this.coordinatorSubmitted,
      createRequestJson: createRequestJson ?? this.createRequestJson,
      createRequestIdempotencyKey:
          createRequestIdempotencyKey ?? this.createRequestIdempotencyKey,
      round1ParticipantIds: round1ParticipantIds ?? this.round1ParticipantIds,
      round2ParticipantIds: round2ParticipantIds ?? this.round2ParticipantIds,
      localStateJson: localStateJson ?? this.localStateJson,
      signedPcztB64: signedPcztB64 ?? this.signedPcztB64,
      broadcastTxid: broadcastTxid ?? this.broadcastTxid,
      broadcastResultSent: broadcastResultSent ?? this.broadcastResultSent,
    );
  }

  static MultisigSigningRequestRecord fromJson(Map<String, Object?> json) {
    return MultisigSigningRequestRecord(
      signingRequestId: _readRequiredString(json, 'signingRequestId'),
      accountUuid: _readRequiredString(json, 'accountUuid'),
      sessionId: _readRequiredString(json, 'sessionId'),
      localParticipantId: _readRequiredString(json, 'localParticipantId'),
      requesterParticipantId: _readRequiredString(
        json,
        'requesterParticipantId',
      ),
      selectedParticipantIds: _readStringList(json['selectedParticipantIds']),
      pcztB64: _readRequiredString(json, 'pcztB64'),
      pcztHash: _readRequiredString(json, 'pcztHash'),
      needsSaplingParams: json['needsSaplingParams'] as bool? ?? false,
      amountZatoshi: json['amountZatoshi'] as String? ?? '0',
      feeZatoshi: json['feeZatoshi'] as String? ?? '0',
      recipientAddress: json['recipientAddress'] as String? ?? '',
      addressType: json['addressType'] as String? ?? '',
      memo: json['memo'] as String?,
      state: json['state'] as String? ?? 'open',
      createdAt: _readInt(json['createdAt']),
      updatedAt: _readInt(json['updatedAt']),
      sendFlowId: json['sendFlowId'] as String?,
      coordinatorSubmitted: json['coordinatorSubmitted'] as bool? ?? true,
      createRequestJson: json['createRequestJson'] as String?,
      createRequestIdempotencyKey:
          json['createRequestIdempotencyKey'] as String?,
      round1ParticipantIds: _readStringList(json['round1ParticipantIds']),
      round2ParticipantIds: _readStringList(json['round2ParticipantIds']),
      localStateJson: json['localStateJson'] as String?,
      signedPcztB64: json['signedPcztB64'] as String?,
      broadcastTxid: json['broadcastTxid'] as String?,
      broadcastResultSent: json['broadcastResultSent'] as bool? ?? false,
    );
  }

  static MultisigSigningRequestRecord fromTxRequestBody({
    required String accountUuid,
    required String localParticipantId,
    required Map<String, Object?> body,
    required int receivedAt,
  }) {
    return MultisigSigningRequestRecord(
      signingRequestId: body['signingRequestId'] as String? ?? '',
      accountUuid: accountUuid,
      sessionId: body['sessionId'] as String? ?? '',
      localParticipantId: localParticipantId,
      requesterParticipantId: body['requesterParticipantId'] as String? ?? '',
      selectedParticipantIds: _readStringList(body['selectedParticipantIds']),
      pcztB64: body['pcztB64'] as String? ?? '',
      pcztHash: body['pcztHash'] as String? ?? '',
      needsSaplingParams: body['needsSaplingParams'] as bool? ?? false,
      amountZatoshi: body['amountZatoshi'] as String? ?? '0',
      feeZatoshi: body['feeZatoshi'] as String? ?? '0',
      recipientAddress: body['recipientAddress'] as String? ?? '',
      addressType: body['addressType'] as String? ?? '',
      memo: body['memo'] as String?,
      state: 'open',
      createdAt: _readInt(body['createdAt']) * 1000,
      updatedAt: receivedAt,
      coordinatorSubmitted: true,
    );
  }
}

class MultisigSigningRequestStore {
  const MultisigSigningRequestStore(this._storage);

  final AppSecureStore _storage;

  Future<List<MultisigSigningRequestRecord>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    final raw = await _storage.readSecretStringWithOptions(
      kMultisigSigningRequestsStorageKey,
      requireUnlockedSession: requireUnlockedSession,
    );
    if (raw == null || raw.trim().isEmpty) {
      return const <MultisigSigningRequestRecord>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <MultisigSigningRequestRecord>[];
    return decoded
        .whereType<Map>()
        .map(
          (entry) => MultisigSigningRequestRecord.fromJson(
            entry.cast<String, Object?>(),
          ),
        )
        .where((entry) => entry.signingRequestId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> writeAll(List<MultisigSigningRequestRecord> records) {
    final encoded = jsonEncode(records.map((entry) => entry.toJson()).toList());
    return _storage.writeSecretString(
      kMultisigSigningRequestsStorageKey,
      encoded,
    );
  }

  Future<void> clearAll() {
    return _storage.delete(kMultisigSigningRequestsStorageKey);
  }
}

abstract class MultisigSendProposalService {
  Future<Uint8List> createPcztFromProposal({
    required String dbPath,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  });

  Future<Uint8List> addProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  });

  Future<rust_sync.ExtractAndBroadcastPcztResult> extractAndBroadcastPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  });

  Future<void> discardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  });
}

class RustMultisigSendProposalService implements MultisigSendProposalService {
  const RustMultisigSendProposalService();

  @override
  Future<Uint8List> createPcztFromProposal({
    required String dbPath,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  }) {
    return rust_sync.createPcztFromProposal(
      dbPath: dbPath,
      network: network,
      proposalId: proposalId,
      sendFlowId: sendFlowId,
    );
  }

  @override
  Future<Uint8List> addProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    return rust_sync.addProofsToPczt(
      pcztBytes: pcztBytes,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> extractAndBroadcastPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) {
    return rust_sync.extractAndBroadcastPczt(
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      network: network,
      pcztWithProofsBytes: pcztWithProofsBytes,
      pcztWithSignaturesBytes: pcztWithSignaturesBytes,
      spendParamsPath: spendParamsPath,
      outputParamsPath: outputParamsPath,
    );
  }

  @override
  Future<void> discardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) {
    return rust_sync.discardProposal(
      proposalId: proposalId,
      sendFlowId: sendFlowId,
    );
  }
}

final multisigSigningRequestStoreProvider =
    Provider<MultisigSigningRequestStore>(
      (ref) => MultisigSigningRequestStore(AppSecureStore.instance),
    );

final multisigSendProposalServiceProvider =
    Provider<MultisigSendProposalService>(
      (ref) => const RustMultisigSendProposalService(),
    );

class MultisigSigningRequestsNotifier
    extends AsyncNotifier<List<MultisigSigningRequestRecord>> {
  MultisigSigningRequestStore get _store =>
      ref.read(multisigSigningRequestStoreProvider);

  MultisigAccountMaterialStore get _materialStore =>
      ref.read(multisigAccountMaterialStoreProvider);

  MultisigCoordinatorService get _coordinator =>
      ref.read(multisigCoordinatorServiceProvider);

  MultisigSendProposalService get _proposalService =>
      ref.read(multisigSendProposalServiceProvider);

  @override
  FutureOr<List<MultisigSigningRequestRecord>> build() {
    final security = ref.watch(appSecurityProvider);
    if (security.requiresUnlock) {
      return const <MultisigSigningRequestRecord>[];
    }
    return _load();
  }

  Future<MultisigSigningDraft> loadDraft(String accountUuid) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(accountUuid),
    );
    await _ensureLocalBackupCompleted(material);
    return _withAuthRetry(material, (freshMaterial) async {
      final session = await _coordinator.getSession(
        coordinatorUrl: freshMaterial.coordinatorUrl,
        sessionId: freshMaterial.sessionId,
        accessToken: freshMaterial.accessToken,
      );
      final participants =
          session.participants.map(MultisigSigningParticipant.fromApi).toList()
            ..sort((a, b) => a.displayName.compareTo(b.displayName));
      return MultisigSigningDraft(
        material: freshMaterial,
        threshold: session.threshold ?? freshMaterial.threshold,
        participants: participants,
      );
    });
  }

  Future<MultisigSigningRequestRecord> createRequest({
    required String accountUuid,
    required BigInt proposalId,
    required String sendFlowId,
    required String recipientAddress,
    required BigInt amountZatoshi,
    required BigInt feeZatoshi,
    required List<String> selectedParticipantIds,
    required bool needsSaplingParams,
    String? addressType,
    String? memo,
    String? dbPath,
    String? network,
  }) async {
    var proposalConsumed = false;
    try {
      final material = await _materialWithFreshAccess(
        await _materialForAccount(accountUuid),
      );
      await _ensureLocalBackupCompleted(material);
      final existing = await _recordForSendFlow(accountUuid, sendFlowId);
      if (existing != null) {
        proposalConsumed = true;
        return _prepareOrSubmitCreate(existing, material);
      }
      if (!selectedParticipantIds.contains(material.participantId)) {
        throw StateError('Requester must be included in selected signers.');
      }
      if (selectedParticipantIds.length != material.threshold) {
        throw StateError('Select exactly ${material.threshold} signers.');
      }

      final walletDbPath = dbPath ?? await getWalletDbPath();
      final walletNetwork =
          network ?? ref.read(rpcEndpointProvider).networkName;
      final pcztBytes = await _proposalService.createPcztFromProposal(
        dbPath: walletDbPath,
        network: walletNetwork,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
      );
      proposalConsumed = true;

      final now = DateTime.now().millisecondsSinceEpoch;
      final record = MultisigSigningRequestRecord(
        signingRequestId: _localSigningRequestId(sendFlowId),
        accountUuid: accountUuid,
        sessionId: material.sessionId,
        localParticipantId: material.participantId,
        requesterParticipantId: material.participantId,
        selectedParticipantIds: selectedParticipantIds,
        pcztB64: _base64UrlNoPad(pcztBytes),
        pcztHash: _pcztHash(pcztBytes),
        needsSaplingParams: needsSaplingParams,
        amountZatoshi: amountZatoshi.toString(),
        feeZatoshi: feeZatoshi.toString(),
        recipientAddress: recipientAddress,
        addressType: addressType ?? '',
        memo: _cleanOptional(memo),
        state: 'requested',
        createdAt: now,
        updatedAt: now,
        sendFlowId: sendFlowId,
        coordinatorSubmitted: false,
      );
      await _upsert(record);
      return _prepareOrSubmitCreate(record, material);
    } finally {
      if (!proposalConsumed) {
        await _proposalService.discardProposal(
          proposalId: proposalId,
          sendFlowId: sendFlowId,
        );
      }
    }
  }

  Future<MultisigSigningRequestRecord> createDraftFromProposal({
    required String dbPath,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
    required String accountUuid,
    required String recipientAddress,
    required String addressType,
    required BigInt amountZatoshi,
    required BigInt feeZatoshi,
    required bool needsSaplingParams,
    String? memo,
  }) async {
    var proposalConsumed = false;
    try {
      final existing = await _recordForSendFlow(accountUuid, sendFlowId);
      if (existing != null) return existing;

      final material = await _materialForAccount(accountUuid);
      await _ensureLocalBackupCompleted(material);

      final pcztBytes = await _proposalService.createPcztFromProposal(
        dbPath: dbPath,
        network: network,
        proposalId: proposalId,
        sendFlowId: sendFlowId,
      );
      proposalConsumed = true;

      final now = DateTime.now().millisecondsSinceEpoch;
      final record = MultisigSigningRequestRecord(
        signingRequestId: 'draft_$sendFlowId',
        accountUuid: accountUuid,
        sessionId: material.sessionId,
        localParticipantId: material.participantId,
        requesterParticipantId: material.participantId,
        selectedParticipantIds: const <String>[],
        pcztB64: _base64UrlNoPad(pcztBytes),
        pcztHash: _pcztHash(pcztBytes),
        needsSaplingParams: needsSaplingParams,
        amountZatoshi: amountZatoshi.toString(),
        feeZatoshi: feeZatoshi.toString(),
        recipientAddress: recipientAddress,
        addressType: addressType,
        memo: _cleanOptional(memo),
        state: multisigSigningDraftState,
        createdAt: now,
        updatedAt: now,
        sendFlowId: sendFlowId,
        coordinatorSubmitted: false,
      );
      await _upsert(record);
      return record;
    } finally {
      if (!proposalConsumed) {
        await _proposalService.discardProposal(
          proposalId: proposalId,
          sendFlowId: sendFlowId,
        );
      }
    }
  }

  Future<MultisigSigningRequestRecord> submitPreparedRequest(
    MultisigSigningRequestRecord record,
  ) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(record.accountUuid),
    );
    await _ensureLocalBackupCompleted(material);
    return _prepareOrSubmitCreate(record, material);
  }

  Future<MultisigSigningRequestRecord> submitRound1(
    MultisigSigningRequestRecord record,
  ) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(record.accountUuid),
    );
    await _ensureLocalBackupCompleted(material);
    return _withAuthRetry(material, (freshMaterial) async {
      final current = await _findRecord(
        record.signingRequestId,
        fallback: record,
      );
      return _submitRound1WithMaterial(current, freshMaterial);
    });
  }

  Future<MultisigSigningRequestRecord> submitRound2(
    MultisigSigningRequestRecord record,
  ) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(record.accountUuid),
    );
    await _ensureLocalBackupCompleted(material);
    return _withAuthRetry(material, (freshMaterial) async {
      final current = await _findRecord(
        record.signingRequestId,
        fallback: record,
      );
      return _submitRound2WithMaterial(current, freshMaterial);
    });
  }

  Future<MultisigSigningRequestRecord> aggregateSignedPczt(
    MultisigSigningRequestRecord record,
  ) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(record.accountUuid),
    );
    await _ensureLocalBackupCompleted(material);
    return _withAuthRetry(material, (freshMaterial) async {
      final current = await _findRecord(
        record.signingRequestId,
        fallback: record,
      );
      return _aggregateSignedPcztWithMaterial(current, freshMaterial);
    });
  }

  Future<MultisigSigningRequestRecord> broadcast(
    MultisigSigningRequestRecord record, {
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(record.accountUuid),
    );
    await _ensureLocalBackupCompleted(material);
    return _withAuthRetry(material, (freshMaterial) async {
      final current = await _findRecord(
        record.signingRequestId,
        fallback: record,
      );
      return _broadcastWithMaterial(
        current,
        freshMaterial,
        spendParamsPath: spendParamsPath,
        outputParamsPath: outputParamsPath,
      );
    });
  }

  Future<void> refreshForAccount(String accountUuid) async {
    final material = await _materialWithFreshAccess(
      await _materialForAccount(accountUuid),
    );
    await _withAuthRetry(material, _refreshForAccountWithMaterial);
  }

  Future<void> deleteForAccount(String accountUuid) async {
    final current = await _currentRecords();
    final next = [
      for (final record in current)
        if (record.accountUuid != accountUuid) record,
    ];
    if (next.length == current.length) return;
    await _save(next);
    state = AsyncData(_sorted(next));
  }

  Future<void> clearAll() async {
    await _store.clearAll();
    state = const AsyncData(<MultisigSigningRequestRecord>[]);
  }

  Future<MultisigSigningRequestRecord> _prepareOrSubmitCreate(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material,
  ) async {
    if (record.coordinatorSubmitted) return record;
    if (_hasPreparedCreate(record)) {
      return _submitPreparedCreate(record, material);
    }
    return _prepareCreate(record, material);
  }

  Future<MultisigSigningRequestRecord> _prepareCreate(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material,
  ) async {
    final sendFlowId = record.sendFlowId;
    if (sendFlowId == null || sendFlowId.trim().isEmpty) {
      throw StateError('Local multisig signing request is missing send flow.');
    }
    final pcztBytes = _decodeBase64UrlNoPad(record.pcztB64);
    final prepared = await _withAuthRetry(material, (freshMaterial) {
      return _coordinator.prepareSigningRequest(
        coordinatorUrl: freshMaterial.coordinatorUrl,
        sessionId: freshMaterial.sessionId,
        participantId: freshMaterial.participantId,
        accessToken: freshMaterial.accessToken,
        rosterHash: freshMaterial.rosterHash,
        requestSeed: sendFlowId,
        selectedParticipantIds: record.selectedParticipantIds,
        pcztBytes: pcztBytes,
        needsSaplingParams: record.needsSaplingParams,
        amountZatoshi: record.amountZatoshi,
        feeZatoshi: record.feeZatoshi,
        recipientAddress: record.recipientAddress,
        memo: _cleanOptional(record.memo),
      );
    });
    final updated = MultisigSigningRequestRecord(
      signingRequestId: prepared.signingRequestId,
      accountUuid: record.accountUuid,
      sessionId: prepared.sessionId,
      localParticipantId: record.localParticipantId,
      requesterParticipantId: prepared.requesterParticipantId,
      selectedParticipantIds: prepared.selectedParticipantIds,
      pcztB64: record.pcztB64,
      pcztHash: prepared.pcztHash,
      needsSaplingParams: record.needsSaplingParams,
      amountZatoshi: record.amountZatoshi,
      feeZatoshi: record.feeZatoshi,
      recipientAddress: record.recipientAddress,
      addressType: record.addressType,
      memo: record.memo,
      state: 'requested',
      createdAt: prepared.createdAt.toInt() * 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      sendFlowId: record.sendFlowId,
      coordinatorSubmitted: false,
      createRequestJson: prepared.requestJson,
      createRequestIdempotencyKey: prepared.idempotencyKey,
    );
    await _replaceRecord(record.signingRequestId, updated);
    return _submitPreparedCreate(updated, material);
  }

  Future<MultisigSigningRequestRecord> _submitPreparedCreate(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material,
  ) async {
    final requestJson = record.createRequestJson;
    final idempotencyKey = record.createRequestIdempotencyKey;
    if (requestJson == null ||
        requestJson.trim().isEmpty ||
        idempotencyKey == null ||
        idempotencyKey.trim().isEmpty) {
      throw StateError('Prepared multisig signing request is missing.');
    }
    try {
      return await _withAuthRetry(material, (freshMaterial) async {
        final signing = await _coordinator.submitPreparedSigningRequest(
          coordinatorUrl: freshMaterial.coordinatorUrl,
          sessionId: record.sessionId,
          accessToken: freshMaterial.accessToken,
          pcztHash: record.pcztHash,
          requestJson: requestJson,
          idempotencyKey: idempotencyKey,
        );
        final updated = record.copyWith(
          state: signing.state,
          coordinatorSubmitted: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _upsert(updated);
        return updated;
      });
    } catch (e) {
      final parsed = MultisigOperationException.from(e);
      final recovered = await _recoverPreparedCreateConflict(record, parsed);
      if (recovered != null) return recovered;
      throw parsed;
    }
  }

  Future<MultisigSigningRequestRecord> _submitRound1WithMaterial(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material,
  ) async {
    final result = await _coordinator.submitSigningRound1(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: record.sessionId,
      signingRequestId: record.signingRequestId,
      participantId: material.participantId,
      accessToken: material.accessToken,
      rosterHash: material.rosterHash,
      selectedParticipantIds: record.selectedParticipantIds,
      pcztBytes: _decodeBase64UrlNoPad(record.pcztB64),
      keyPackageB64: material.keyPackageB64,
      localStateJson: record.localStateJson,
    );
    final round1 = {
      ...record.round1ParticipantIds,
      if (result.submitted) material.participantId,
    }.toList()..sort();
    final updated = record.copyWith(
      localStateJson: result.localStateJson,
      round1ParticipantIds: round1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsert(updated);
    if (!result.submitted) {
      if (multisigErrorLooksIdempotencyInProgress(result.detail)) {
        return updated;
      }
      throw StateError(result.detail);
    }
    await refreshForAccount(record.accountUuid);
    return _findRecord(record.signingRequestId, fallback: updated);
  }

  Future<MultisigSigningRequestRecord> _submitRound2WithMaterial(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material,
  ) async {
    final result = await _coordinator.submitSigningRound2(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: record.sessionId,
      signingRequestId: record.signingRequestId,
      participantId: material.participantId,
      accessToken: material.accessToken,
      rosterHash: material.rosterHash,
      deliverySecretKey: material.identity.deliverySecretKey,
      selectedParticipantIds: record.selectedParticipantIds,
      pcztBytes: _decodeBase64UrlNoPad(record.pcztB64),
      keyPackageB64: material.keyPackageB64,
      localStateJson: record.localStateJson,
    );
    final round2 = {
      ...record.round2ParticipantIds,
      if (result.submitted) material.participantId,
    }.toList()..sort();
    final updated = record.copyWith(
      localStateJson: result.localStateJson,
      round2ParticipantIds: round2,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsert(updated);
    if (!result.submitted) {
      if (multisigErrorLooksIdempotencyInProgress(result.detail)) {
        return updated;
      }
      throw StateError(result.detail);
    }
    await refreshForAccount(record.accountUuid);
    return _findRecord(record.signingRequestId, fallback: updated);
  }

  Future<MultisigSigningRequestRecord> _aggregateSignedPcztWithMaterial(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material,
  ) async {
    final result = await _coordinator.aggregateSignedPczt(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: record.sessionId,
      signingRequestId: record.signingRequestId,
      participantId: material.participantId,
      accessToken: material.accessToken,
      rosterHash: material.rosterHash,
      deliverySecretKey: material.identity.deliverySecretKey,
      selectedParticipantIds: record.selectedParticipantIds,
      pcztBytes: _decodeBase64UrlNoPad(record.pcztB64),
      groupPublicPackageJson: material.groupPublicPackageJson,
      localStateJson: record.localStateJson,
    );
    final updated = record.copyWith(
      localStateJson: result.localStateJson,
      signedPcztB64: _base64UrlNoPad(result.signedPcztBytes),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsert(updated);
    return updated;
  }

  Future<MultisigSigningRequestRecord> _broadcastWithMaterial(
    MultisigSigningRequestRecord record,
    MultisigAccountMaterial material, {
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    final signedRecord =
        record.signedPcztB64 == null || record.signedPcztB64!.isEmpty
        ? await _aggregateSignedPcztWithMaterial(record, material)
        : record;
    var current = signedRecord;
    var txid = current.broadcastTxid;
    if (txid == null || txid.isEmpty) {
      final pcztBytes = _decodeBase64UrlNoPad(current.pcztB64);
      final signedPcztBytes = _decodeBase64UrlNoPad(current.signedPcztB64!);
      final pcztWithProofs = await _proposalService.addProofsToPczt(
        pcztBytes: pcztBytes,
        spendParamsPath: current.needsSaplingParams ? spendParamsPath : null,
        outputParamsPath: current.needsSaplingParams ? outputParamsPath : null,
      );
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final result = await _proposalService.extractAndBroadcastPczt(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        pcztWithProofsBytes: pcztWithProofs,
        pcztWithSignaturesBytes: signedPcztBytes,
        spendParamsPath: current.needsSaplingParams ? spendParamsPath : null,
        outputParamsPath: current.needsSaplingParams ? outputParamsPath : null,
      );
      if (result.status == 'broadcast_unknown') {
        final switched = await ref
            .read(rpcEndpointFailoverProvider.notifier)
            .switchToFallbackFor(
              result.message ?? 'multisig broadcast status unknown',
              endpoint: endpoint,
              operation: 'multisig broadcast',
            );
        if (switched) {
          await ref.read(syncProvider.notifier).restartSync();
        }
        throw StateError(result.message ?? 'Broadcast status is unknown.');
      }
      txid = result.txid;
      current = current.copyWith(
        broadcastTxid: txid,
        broadcastResultSent: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _upsert(current);
    }
    final notified = await _coordinator.postBroadcastResult(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: current.sessionId,
      signingRequestId: current.signingRequestId,
      participantId: material.participantId,
      accessToken: material.accessToken,
      rosterHash: material.rosterHash,
      selectedParticipantIds: current.selectedParticipantIds,
      pcztHash: current.pcztHash,
      txid: txid,
      localStateJson: current.localStateJson,
    );
    final updated = current.copyWith(
      state: 'completed',
      localStateJson: notified.localStateJson,
      broadcastTxid: txid,
      broadcastResultSent: notified.submitted,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _upsert(updated);
    if (!notified.submitted) {
      if (multisigErrorLooksIdempotencyInProgress(notified.detail)) {
        return updated;
      }
      throw StateError(notified.detail);
    }
    try {
      await ref.read(syncProvider.notifier).refreshAfterSend();
    } catch (_) {}
    return updated;
  }

  Future<void> _refreshForAccountWithMaterial(
    MultisigAccountMaterial material,
  ) async {
    final inbox = await _coordinator.getSigningInbox(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: material.sessionId,
      participantId: material.participantId,
      accessToken: material.accessToken,
      rosterHash: material.rosterHash,
      deliverySecretKey: material.identity.deliverySecretKey,
      after: 0,
    );
    final records = [...await _currentRecords()];
    var changed = false;
    for (final message in inbox.messages) {
      final plaintext = message.plaintextJson;
      if (plaintext == null || plaintext.trim().isEmpty) continue;
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map) continue;
      final body = decoded.cast<String, Object?>();
      if (message.kind == 'tx_request') {
        final incoming = MultisigSigningRequestRecord.fromTxRequestBody(
          accountUuid: material.accountUuid,
          localParticipantId: material.participantId,
          body: body,
          receivedAt: message.createdAt.toInt() * 1000,
        );
        if (incoming.signingRequestId.isEmpty) continue;
        changed = _mergeRecord(records, incoming) || changed;
        continue;
      }

      final relatedId = message.relatedId;
      if (relatedId == null || relatedId.isEmpty) continue;
      final index = records.indexWhere(
        (entry) => entry.signingRequestId == relatedId,
      );
      if (index < 0) continue;
      final participantId = message.fromParticipantId;
      if (message.kind == 'tx_round1') {
        final round1 = {
          ...records[index].round1ParticipantIds,
          participantId,
        }.toList()..sort();
        records[index] = records[index].copyWith(
          round1ParticipantIds: round1,
          updatedAt: message.createdAt.toInt() * 1000,
        );
        changed = true;
      } else if (message.kind == 'tx_round2') {
        final round2 = {
          ...records[index].round2ParticipantIds,
          participantId,
        }.toList()..sort();
        records[index] = records[index].copyWith(
          round2ParticipantIds: round2,
          updatedAt: message.createdAt.toInt() * 1000,
        );
        changed = true;
      } else if (message.kind == 'broadcast_result') {
        records[index] = records[index].copyWith(
          state: 'completed',
          broadcastTxid: body['txid'] as String?,
          broadcastResultSent: true,
          updatedAt: message.createdAt.toInt() * 1000,
        );
        changed = true;
      }
    }
    if (changed) {
      await _save(records);
      state = AsyncData(_sorted(records));
    }
  }

  Future<MultisigAccountMaterial> _materialForAccount(
    String accountUuid,
  ) async {
    final material = await _materialStore.read(accountUuid);
    if (material == null) {
      throw StateError('Multisig material not found for this account.');
    }
    return material;
  }

  Future<void> _ensureLocalBackupCompleted(
    MultisigAccountMaterial material,
  ) async {
    if (multisigMaterialBackupCompleted(material)) return;
    final sessions = await ref.read(multisigPendingSessionsProvider.future);
    final session = multisigSessionByStorageId(sessions, material.storageId);
    if (session == null || !session.localBackupCompleted) {
      throw StateError(
        'Confirm the local multisig backup before signing with this account.',
      );
    }
  }

  Future<T> _withAuthRetry<T>(
    MultisigAccountMaterial material,
    Future<T> Function(MultisigAccountMaterial material) operation,
  ) async {
    try {
      return await operation(material);
    } catch (e) {
      final parsed = MultisigOperationException.from(e);
      if (!parsed.isUnauthorized) {
        throw parsed;
      }
      final refreshed = await _materialWithFreshAccess(material, force: true);
      try {
        return await operation(refreshed);
      } catch (retryError) {
        throw MultisigOperationException.from(retryError);
      }
    }
  }

  Future<MultisigSigningRequestRecord?> _recoverPreparedCreateConflict(
    MultisigSigningRequestRecord record,
    MultisigOperationException error,
  ) async {
    if (error.isIdempotencyInProgress) {
      await _refreshForAccountSilently(record.accountUuid);
      return await _findRecordOrNull(record.signingRequestId) ?? record;
    }

    if (!error.isDuplicateSigningRequestId) return null;

    await _refreshForAccountSilently(record.accountUuid);
    final refreshed = await _findRecordOrNull(record.signingRequestId);
    if (refreshed == null) return null;
    if (refreshed.pcztHash != record.pcztHash) return null;
    if (!refreshed.coordinatorSubmitted) return null;
    return refreshed;
  }

  Future<void> _refreshForAccountSilently(String accountUuid) async {
    try {
      await refreshForAccount(accountUuid);
    } catch (_) {}
  }

  Future<MultisigAccountMaterial> _materialWithFreshAccess(
    MultisigAccountMaterial material, {
    bool force = false,
  }) async {
    if (!force && _hasFreshAccess(material)) return material;

    final update = await _coordinator.refreshOrResumeAuth(
      coordinatorUrl: material.coordinatorUrl,
      sessionId: material.sessionId,
      participantId: material.participantId,
      refreshToken: material.refreshToken,
      admissionSecretKey: material.identity.admissionSecretKey,
      deliverySecretKey: material.identity.deliverySecretKey,
    );
    _validateAuthOwner(
      expectedSessionId: material.sessionId,
      expectedParticipantId: material.participantId,
      returnedSessionId: update.sessionId,
      returnedParticipantId: update.participantId,
    );
    await ref
        .read(multisigPendingSessionsProvider.notifier)
        .applyAuthUpdate(update);
    final refreshed = material.copyWith(
      identity: MultisigParticipantIdentity(
        admissionSecretKey: material.identity.admissionSecretKey,
        admissionPublicKey: update.admissionPublicKey,
        deliverySecretKey: update.deliverySecretKey,
        deliveryPublicKey: update.deliveryPublicKey,
      ),
      accessToken: update.accessToken,
      refreshToken: update.refreshToken,
      accessTokenExpiresAt: update.accessTokenExpiresAt.toInt(),
      refreshTokenExpiresAt: update.refreshTokenExpiresAt.toInt(),
    );
    await _materialStore.write(refreshed);
    return refreshed;
  }

  bool _hasFreshAccess(MultisigAccountMaterial material) {
    final nowSeconds =
        ref.read(multisigNowProvider)().millisecondsSinceEpoch ~/ 1000;
    return material.accessTokenExpiresAt >
        nowSeconds + _accessTokenRefreshSkewSeconds;
  }

  Future<void> _upsert(MultisigSigningRequestRecord record) async {
    final records = [...await _currentRecords()];
    _mergeRecord(records, record);
    await _save(records);
    state = AsyncData(_sorted(records));
  }

  Future<void> _replaceRecord(
    String previousSigningRequestId,
    MultisigSigningRequestRecord record,
  ) async {
    final records = [...await _currentRecords()];
    if (previousSigningRequestId != record.signingRequestId) {
      records.removeWhere(
        (entry) => entry.signingRequestId == previousSigningRequestId,
      );
    }
    _mergeRecord(records, record);
    await _save(records);
    state = AsyncData(_sorted(records));
  }

  bool _mergeRecord(
    List<MultisigSigningRequestRecord> records,
    MultisigSigningRequestRecord incoming,
  ) {
    final index = records.indexWhere(
      (entry) => entry.signingRequestId == incoming.signingRequestId,
    );
    if (index < 0) {
      records.add(incoming);
      return true;
    }
    final current = records[index];
    final round1 = {
      ...current.round1ParticipantIds,
      ...incoming.round1ParticipantIds,
    }.toList()..sort();
    final round2 = {
      ...current.round2ParticipantIds,
      ...incoming.round2ParticipantIds,
    }.toList()..sort();
    records[index] = incoming.copyWith(
      state: current.state == 'completed' ? current.state : incoming.state,
      updatedAt: incoming.updatedAt > current.updatedAt
          ? incoming.updatedAt
          : current.updatedAt,
      sendFlowId: incoming.sendFlowId ?? current.sendFlowId,
      round1ParticipantIds: round1,
      round2ParticipantIds: round2,
      coordinatorSubmitted:
          current.coordinatorSubmitted || incoming.coordinatorSubmitted,
      createRequestJson:
          incoming.createRequestJson ?? current.createRequestJson,
      createRequestIdempotencyKey:
          incoming.createRequestIdempotencyKey ??
          current.createRequestIdempotencyKey,
      localStateJson: incoming.localStateJson ?? current.localStateJson,
      signedPcztB64: incoming.signedPcztB64 ?? current.signedPcztB64,
      broadcastTxid: incoming.broadcastTxid ?? current.broadcastTxid,
      broadcastResultSent:
          current.broadcastResultSent || incoming.broadcastResultSent,
    );
    return true;
  }

  Future<MultisigSigningRequestRecord> _findRecord(
    String signingRequestId, {
    required MultisigSigningRequestRecord fallback,
  }) async {
    return await _findRecordOrNull(signingRequestId) ?? fallback;
  }

  Future<MultisigSigningRequestRecord?> _findRecordOrNull(
    String signingRequestId,
  ) async {
    for (final record in await _currentRecords()) {
      if (record.signingRequestId == signingRequestId) return record;
    }
    return null;
  }

  Future<MultisigSigningRequestRecord?> _recordForSendFlow(
    String accountUuid,
    String sendFlowId,
  ) async {
    for (final record in await _currentRecords()) {
      if (record.accountUuid == accountUuid &&
          record.sendFlowId == sendFlowId) {
        return record;
      }
    }
    return null;
  }

  Future<List<MultisigSigningRequestRecord>> _currentRecords() async {
    final current = state.value;
    if (current != null) return current;
    return _load();
  }

  Future<List<MultisigSigningRequestRecord>> _load() async {
    return _sorted(await _store.readAll());
  }

  Future<void> _save(List<MultisigSigningRequestRecord> records) {
    return _store.writeAll(_sorted(records));
  }
}

final multisigSigningRequestsProvider =
    AsyncNotifierProvider<
      MultisigSigningRequestsNotifier,
      List<MultisigSigningRequestRecord>
    >(MultisigSigningRequestsNotifier.new);

List<MultisigSigningRequestRecord> _sorted(
  List<MultisigSigningRequestRecord> records,
) {
  return [...records]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}

String _pcztHash(List<int> pcztBytes) {
  return base64Url.encode(sha256.convert(pcztBytes).bytes).replaceAll('=', '');
}

String _localSigningRequestId(String sendFlowId) => 'local_$sendFlowId';

bool _hasPreparedCreate(MultisigSigningRequestRecord record) {
  return record.createRequestJson != null &&
      record.createRequestJson!.trim().isNotEmpty &&
      record.createRequestIdempotencyKey != null &&
      record.createRequestIdempotencyKey!.trim().isNotEmpty;
}

String _base64UrlNoPad(List<int> value) {
  return base64Url.encode(value).replaceAll('=', '');
}

Uint8List _decodeBase64UrlNoPad(String value) {
  final normalized = value.padRight(
    value.length + (4 - value.length % 4) % 4,
    '=',
  );
  return Uint8List.fromList(base64Url.decode(normalized));
}

String _readRequiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Multisig signing request is missing $key.');
  }
  return value;
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value.whereType<String>().where((entry) => entry.isNotEmpty).toList();
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String? _cleanOptional(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String _shortId(String value) {
  if (value.length <= 12) return value;
  return '${value.substring(0, 6)}...${value.substring(value.length - 6)}';
}

void _validateAuthOwner({
  required String expectedSessionId,
  required String expectedParticipantId,
  required String returnedSessionId,
  required String returnedParticipantId,
}) {
  if (returnedSessionId != expectedSessionId ||
      returnedParticipantId != expectedParticipantId) {
    throw StateError('Coordinator returned auth for a different participant.');
  }
}
