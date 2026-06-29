import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_coordinator_service.dart';
import 'package:zcash_wallet/src/providers/multisig_signing_request_provider.dart';
import 'package:zcash_wallet/src/rust/api/multisig.dart' as rust_multisig;
import 'package:zcash_wallet/src/rust/api/sync.dart';

void main() {
  test('creates a local draft from a stored send proposal', () async {
    final requestStore = _FakeSigningRequestStore();
    final materialStore = _FakeAccountMaterialStore()
      ..put(_accountMaterial(localBackupCompletedAt: 10));
    final proposalService = _FakeProposalService(
      pcztBytes: Uint8List.fromList([1, 2, 3]),
    );
    final container = _container(
      requestStore: requestStore,
      materialStore: materialStore,
      proposalService: proposalService,
    );
    addTearDown(container.dispose);

    final record = await container
        .read(multisigSigningRequestsProvider.notifier)
        .createDraftFromProposal(
          dbPath: '/tmp/wallet.db',
          network: 'test',
          proposalId: BigInt.from(7),
          sendFlowId: 'flow-1',
          accountUuid: 'account-1',
          recipientAddress: 'u1recipient',
          addressType: 'unified',
          amountZatoshi: BigInt.from(1000),
          feeZatoshi: BigInt.from(100),
          needsSaplingParams: true,
          memo: ' memo ',
        );

    expect(proposalService.createCalls, ['7|flow-1|test|/tmp/wallet.db']);
    expect(proposalService.discardCalls, isEmpty);
    expect(record.signingRequestId, 'draft_flow-1');
    expect(record.state, multisigSigningDraftState);
    expect(record.accountUuid, 'account-1');
    expect(record.sessionId, 'session-1');
    expect(record.localParticipantId, 'participant-1');
    expect(record.selectedParticipantIds, isEmpty);
    expect(record.pcztB64, 'AQID');
    expect(record.pcztHash, isNotEmpty);
    expect(record.needsSaplingParams, isTrue);
    expect(record.amountZatoshi, '1000');
    expect(record.feeZatoshi, '100');
    expect(record.memo, 'memo');
    expect(requestStore.records, [record]);
  });

  test('discard proposal when local material is not ready', () async {
    final requestStore = _FakeSigningRequestStore();
    final materialStore = _FakeAccountMaterialStore()..put(_accountMaterial());
    final proposalService = _FakeProposalService();
    final container = _container(
      requestStore: requestStore,
      materialStore: materialStore,
      proposalService: proposalService,
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(multisigSigningRequestsProvider.notifier)
          .createDraftFromProposal(
            dbPath: '/tmp/wallet.db',
            network: 'test',
            proposalId: BigInt.from(7),
            sendFlowId: 'flow-1',
            accountUuid: 'account-1',
            recipientAddress: 'u1recipient',
            addressType: 'unified',
            amountZatoshi: BigInt.from(1000),
            feeZatoshi: BigInt.from(100),
            needsSaplingParams: false,
          ),
      throwsA(isA<StateError>()),
    );

    expect(proposalService.createCalls, isEmpty);
    expect(proposalService.discardCalls, ['7|flow-1']);
    expect(requestStore.records, isEmpty);
  });

  test(
    'keeps consumed PCZT when prepare fails and retries from local record',
    () async {
      final requestStore = _FakeSigningRequestStore();
      final materialStore = _FakeAccountMaterialStore()
        ..put(
          _accountMaterial(
            localBackupCompletedAt: 10,
            accessTokenExpiresAt: 9999999999,
          ),
        );
      final proposalService = _FakeProposalService(
        pcztBytes: Uint8List.fromList([1, 2, 3]),
      );
      final coordinator = _FakeCoordinatorService(failPrepareOnce: true);
      final container = _container(
        requestStore: requestStore,
        materialStore: materialStore,
        proposalService: proposalService,
        coordinatorService: coordinator,
      );
      addTearDown(container.dispose);

      final notifier = container.read(multisigSigningRequestsProvider.notifier);

      await expectLater(
        notifier.createRequest(
          dbPath: '/tmp/wallet.db',
          network: 'test',
          proposalId: BigInt.from(7),
          sendFlowId: 'flow-1',
          accountUuid: 'account-1',
          recipientAddress: 'u1recipient',
          addressType: 'unified',
          amountZatoshi: BigInt.from(1000),
          feeZatoshi: BigInt.from(100),
          selectedParticipantIds: const ['participant-1', 'participant-2'],
          needsSaplingParams: true,
          memo: ' memo ',
        ),
        throwsA(anything),
      );

      expect(proposalService.createCalls, ['7|flow-1|test|/tmp/wallet.db']);
      expect(proposalService.discardCalls, isEmpty);
      expect(coordinator.prepareCalls, hasLength(1));
      expect(coordinator.submitCalls, isEmpty);
      expect(requestStore.records, hasLength(1));
      final localRecord = requestStore.records.single;
      expect(localRecord.signingRequestId, 'local_flow-1');
      expect(localRecord.pcztB64, 'AQID');
      expect(localRecord.selectedParticipantIds, [
        'participant-1',
        'participant-2',
      ]);
      expect(localRecord.createRequestJson, isNull);
      expect(localRecord.coordinatorSubmitted, isFalse);

      final submitted = await notifier.createRequest(
        dbPath: '/tmp/wallet.db',
        network: 'test',
        proposalId: BigInt.from(7),
        sendFlowId: 'flow-1',
        accountUuid: 'account-1',
        recipientAddress: 'u1recipient',
        addressType: 'unified',
        amountZatoshi: BigInt.from(1000),
        feeZatoshi: BigInt.from(100),
        selectedParticipantIds: const ['participant-1', 'participant-2'],
        needsSaplingParams: true,
        memo: ' memo ',
      );

      expect(proposalService.createCalls, ['7|flow-1|test|/tmp/wallet.db']);
      expect(proposalService.discardCalls, isEmpty);
      expect(coordinator.prepareCalls, hasLength(2));
      expect(coordinator.submitCalls, ['signing-request|idempotency']);
      expect(submitted.signingRequestId, 'signing-request');
      expect(submitted.coordinatorSubmitted, isTrue);
      expect(requestStore.records, hasLength(1));
      expect(requestStore.records.single.signingRequestId, 'signing-request');
      expect(requestStore.records.single.pcztB64, 'AQID');
    },
  );

  test(
    'recovers duplicate signing request when refresh finds the submitted request',
    () async {
      final requestStore = _FakeSigningRequestStore()
        ..records = [_preparedRecord(sendFlowId: 'flow-1')];
      final materialStore = _FakeAccountMaterialStore()
        ..put(
          _accountMaterial(
            localBackupCompletedAt: 10,
            accessTokenExpiresAt: 9999999999,
          ),
        );
      final coordinator = _FakeCoordinatorService(
        submitPreparedError: _structuredConflict(
          'signing_request_id already exists',
        ),
        inboxMessages: [_txRequestMessage(signingRequestId: 'signing-request')],
      );
      final container = _container(
        requestStore: requestStore,
        materialStore: materialStore,
        coordinatorService: coordinator,
      );
      addTearDown(container.dispose);

      final submitted = await container
          .read(multisigSigningRequestsProvider.notifier)
          .submitPreparedRequest(requestStore.records.single);

      expect(coordinator.submitCalls, ['signing-request|idempotency']);
      expect(coordinator.inboxCalls, ['session-1|participant-1|0']);
      expect(submitted.signingRequestId, 'signing-request');
      expect(submitted.coordinatorSubmitted, isTrue);
      expect(submitted.pcztHash, 'pczt-hash');
      expect(requestStore.records.single.coordinatorSubmitted, isTrue);
    },
  );

  test(
    'keeps prepared signing request pending while idempotent submit is in progress',
    () async {
      final requestStore = _FakeSigningRequestStore()
        ..records = [_preparedRecord(sendFlowId: 'flow-1')];
      final materialStore = _FakeAccountMaterialStore()
        ..put(
          _accountMaterial(
            localBackupCompletedAt: 10,
            accessTokenExpiresAt: 9999999999,
          ),
        );
      final coordinator = _FakeCoordinatorService(
        submitPreparedError: _structuredConflict(
          'Idempotency-Key request is still in progress',
        ),
      );
      final container = _container(
        requestStore: requestStore,
        materialStore: materialStore,
        coordinatorService: coordinator,
      );
      addTearDown(container.dispose);

      final submitted = await container
          .read(multisigSigningRequestsProvider.notifier)
          .submitPreparedRequest(requestStore.records.single);

      expect(coordinator.submitCalls, ['signing-request|idempotency']);
      expect(submitted.signingRequestId, 'signing-request');
      expect(submitted.coordinatorSubmitted, isFalse);
      expect(requestStore.records.single.coordinatorSubmitted, isFalse);
    },
  );

  test(
    'does not surface idempotent round submission still in progress',
    () async {
      final requestStore = _FakeSigningRequestStore()
        ..records = [_submittedRecord(signingRequestId: 'signing-request')];
      final materialStore = _FakeAccountMaterialStore()
        ..put(
          _accountMaterial(
            localBackupCompletedAt: 10,
            accessTokenExpiresAt: 9999999999,
          ),
        );
      final coordinator = _FakeCoordinatorService(
        round1Response: const rust_multisig.ApiMultisigSigningAdvance(
          localStateJson: '{"outbound":true}',
          detail:
              'Network error while submitting Round 1: {"marker":"zcash_wallet_multisig_error_v1","kind":"conflict","message":"Idempotency-Key request is still in progress","httpStatus":409,"retryable":true}',
          submitted: false,
        ),
      );
      final container = _container(
        requestStore: requestStore,
        materialStore: materialStore,
        coordinatorService: coordinator,
      );
      addTearDown(container.dispose);

      final updated = await container
          .read(multisigSigningRequestsProvider.notifier)
          .submitRound1(requestStore.records.single);

      expect(coordinator.round1Calls, ['signing-request|participant-1']);
      expect(updated.localStateJson, '{"outbound":true}');
      expect(updated.round1ParticipantIds, isEmpty);
      expect(requestStore.records.single.localStateJson, '{"outbound":true}');
    },
  );

  test('deletes draft records for a removed account', () async {
    final requestStore = _FakeSigningRequestStore()
      ..records = [
        _record(accountUuid: 'account-1', sendFlowId: 'flow-1'),
        _record(accountUuid: 'account-2', sendFlowId: 'flow-2'),
      ];
    final container = _container(requestStore: requestStore);
    addTearDown(container.dispose);

    await container
        .read(multisigSigningRequestsProvider.notifier)
        .deleteForAccount('account-1');

    expect(requestStore.records.map((record) => record.accountUuid), [
      'account-2',
    ]);
  });
}

ProviderContainer _container({
  _FakeSigningRequestStore? requestStore,
  _FakeAccountMaterialStore? materialStore,
  _FakeProposalService? proposalService,
  _FakeCoordinatorService? coordinatorService,
}) {
  return ProviderContainer(
    overrides: [
      appSecurityProvider.overrideWith(() => _FakeAppSecurityNotifier()),
      multisigSigningRequestStoreProvider.overrideWithValue(
        requestStore ?? _FakeSigningRequestStore(),
      ),
      multisigAccountMaterialStoreProvider.overrideWithValue(
        materialStore ?? _FakeAccountMaterialStore(),
      ),
      multisigSendProposalServiceProvider.overrideWithValue(
        proposalService ?? _FakeProposalService(),
      ),
      multisigCoordinatorServiceProvider.overrideWithValue(
        coordinatorService ?? _FakeCoordinatorService(),
      ),
    ],
  );
}

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }
}

class _FakeSigningRequestStore implements MultisigSigningRequestStore {
  List<MultisigSigningRequestRecord> records = <MultisigSigningRequestRecord>[];

  @override
  Future<List<MultisigSigningRequestRecord>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    return records;
  }

  @override
  Future<void> writeAll(List<MultisigSigningRequestRecord> records) async {
    this.records = records;
  }

  @override
  Future<void> clearAll() async {
    records = <MultisigSigningRequestRecord>[];
  }
}

class _FakeAccountMaterialStore implements MultisigAccountMaterialStore {
  final materials = <String, MultisigAccountMaterial>{};

  void put(MultisigAccountMaterial material) {
    materials[material.accountUuid] = material;
  }

  @override
  Future<MultisigAccountMaterial?> read(
    String accountUuid, {
    bool requireUnlockedSession = true,
  }) async {
    return materials[accountUuid];
  }

  @override
  Future<List<MultisigAccountMaterial>> readAll({
    bool requireUnlockedSession = true,
  }) async {
    return materials.values.toList(growable: false);
  }

  @override
  Future<void> write(MultisigAccountMaterial material) async {
    materials[material.accountUuid] = material;
  }

  @override
  Future<void> delete(String accountUuid) async {
    materials.remove(accountUuid);
  }
}

class _FakeProposalService implements MultisigSendProposalService {
  _FakeProposalService({Uint8List? pcztBytes})
    : pcztBytes = pcztBytes ?? Uint8List.fromList([9, 9]);

  final Uint8List pcztBytes;
  final createCalls = <String>[];
  final discardCalls = <String>[];

  @override
  Future<Uint8List> createPcztFromProposal({
    required String dbPath,
    required String network,
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    createCalls.add('$proposalId|$sendFlowId|$network|$dbPath');
    return pcztBytes;
  }

  @override
  Future<Uint8List> addProofsToPczt({
    required List<int> pcztBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return Uint8List.fromList(pcztBytes);
  }

  @override
  Future<ExtractAndBroadcastPcztResult> extractAndBroadcastPczt({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    return const ExtractAndBroadcastPcztResult(txid: 'txid', status: 'success');
  }

  @override
  Future<void> discardProposal({
    required BigInt proposalId,
    required String sendFlowId,
  }) async {
    discardCalls.add('$proposalId|$sendFlowId');
  }
}

class _FakeCoordinatorService implements MultisigCoordinatorService {
  _FakeCoordinatorService({
    this.failPrepareOnce = false,
    this.submitPreparedError,
    this.inboxMessages = const <rust_multisig.ApiMultisigSigningMessage>[],
    this.round1Response,
  });

  bool failPrepareOnce;
  final Object? submitPreparedError;
  final List<rust_multisig.ApiMultisigSigningMessage> inboxMessages;
  final rust_multisig.ApiMultisigSigningAdvance? round1Response;
  final prepareCalls = <String>[];
  final submitCalls = <String>[];
  final inboxCalls = <String>[];
  final round1Calls = <String>[];

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
  }) async {
    prepareCalls.add('$sessionId|$participantId|$requestSeed');
    if (failPrepareOnce) {
      failPrepareOnce = false;
      throw StateError('network down');
    }
    return rust_multisig.ApiPreparedMultisigSigningRequest(
      signingRequestId: 'signing-request',
      sessionId: sessionId,
      requesterParticipantId: participantId,
      selectedParticipantIds: selectedParticipantIds,
      requestJson: '{"request":true}',
      idempotencyKey: 'idempotency',
      pcztHash: 'pczt-hash',
      createdAt: BigInt.from(42),
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
  }) async {
    submitCalls.add('signing-request|$idempotencyKey');
    final error = submitPreparedError;
    if (error != null) throw error;
    return rust_multisig.ApiMultisigSigningRequest(
      signingRequestId: 'signing-request',
      sessionId: sessionId,
      requesterParticipantId: 'participant-1',
      selectedParticipantIds: const ['participant-1', 'participant-2'],
      state: 'open',
      createdAt: BigInt.from(42),
      updatedAt: BigInt.from(43),
      pcztHash: pcztHash,
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
  }) async {
    inboxCalls.add('$sessionId|$participantId|$after');
    return rust_multisig.ApiMultisigSigningInbox(
      cursor: 0,
      messages: inboxMessages,
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
  }) async {
    round1Calls.add('$signingRequestId|$participantId');
    return round1Response ??
        const rust_multisig.ApiMultisigSigningAdvance(
          localStateJson: '{"round1":true}',
          detail: 'Round 1 submitted.',
          submitted: true,
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _identity = MultisigParticipantIdentity(
  admissionSecretKey: 'admission-secret',
  admissionPublicKey: 'admission-public',
  deliverySecretKey: 'delivery-secret',
  deliveryPublicKey: 'delivery-public',
);

MultisigAccountMaterial _accountMaterial({
  int? localBackupCompletedAt,
  int accessTokenExpiresAt = 10,
}) {
  return MultisigAccountMaterial(
    accountUuid: 'account-1',
    sessionId: 'session-1',
    participantId: 'participant-1',
    coordinatorUrl: 'https://coordinator.example',
    rosterHash: 'roster',
    groupPublicPackageHash: 'group',
    threshold: 2,
    participantCount: 3,
    identity: _identity,
    keyPackageB64: 'key-package',
    groupPublicPackageJson: '{"group":true}',
    vaultAddress: 'uregtest1example',
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    accessTokenExpiresAt: accessTokenExpiresAt,
    refreshTokenExpiresAt: 20,
    localBackupCompletedAt: localBackupCompletedAt,
  );
}

MultisigSigningRequestRecord _record({
  required String accountUuid,
  required String sendFlowId,
}) {
  return MultisigSigningRequestRecord(
    signingRequestId: 'draft_$sendFlowId',
    accountUuid: accountUuid,
    sessionId: 'session-1',
    localParticipantId: 'participant-1',
    requesterParticipantId: 'participant-1',
    selectedParticipantIds: const <String>[],
    pcztB64: 'AQID',
    pcztHash: 'hash',
    needsSaplingParams: false,
    amountZatoshi: '1000',
    feeZatoshi: '100',
    recipientAddress: 'u1recipient',
    addressType: 'unified',
    state: multisigSigningDraftState,
    createdAt: 1,
    updatedAt: 1,
    sendFlowId: sendFlowId,
  );
}

MultisigSigningRequestRecord _preparedRecord({required String sendFlowId}) {
  return MultisigSigningRequestRecord(
    signingRequestId: 'signing-request',
    accountUuid: 'account-1',
    sessionId: 'session-1',
    localParticipantId: 'participant-1',
    requesterParticipantId: 'participant-1',
    selectedParticipantIds: const <String>['participant-1', 'participant-2'],
    pcztB64: 'AQID',
    pcztHash: 'pczt-hash',
    needsSaplingParams: false,
    amountZatoshi: '1000',
    feeZatoshi: '100',
    recipientAddress: 'u1recipient',
    addressType: 'unified',
    state: 'requested',
    createdAt: 1,
    updatedAt: 1,
    sendFlowId: sendFlowId,
    coordinatorSubmitted: false,
    createRequestJson: '{"request":true}',
    createRequestIdempotencyKey: 'idempotency',
  );
}

MultisigSigningRequestRecord _submittedRecord({
  required String signingRequestId,
}) {
  return MultisigSigningRequestRecord(
    signingRequestId: signingRequestId,
    accountUuid: 'account-1',
    sessionId: 'session-1',
    localParticipantId: 'participant-1',
    requesterParticipantId: 'participant-1',
    selectedParticipantIds: const <String>['participant-1', 'participant-2'],
    pcztB64: 'AQID',
    pcztHash: 'pczt-hash',
    needsSaplingParams: false,
    amountZatoshi: '1000',
    feeZatoshi: '100',
    recipientAddress: 'u1recipient',
    addressType: 'unified',
    state: 'open',
    createdAt: 1,
    updatedAt: 1,
    coordinatorSubmitted: true,
  );
}

rust_multisig.ApiMultisigSigningMessage _txRequestMessage({
  required String signingRequestId,
}) {
  return rust_multisig.ApiMultisigSigningMessage(
    cursor: 1,
    messageId: 'message-1',
    sessionId: 'session-1',
    kind: 'tx_request',
    fromParticipantId: 'participant-1',
    toParticipantId: 'participant-1',
    relatedId: signingRequestId,
    plaintextJson: jsonEncode({
      'version': 1,
      'kind': 'tx_request',
      'signingRequestId': signingRequestId,
      'sessionId': 'session-1',
      'requesterParticipantId': 'participant-1',
      'selectedParticipantIds': ['participant-1', 'participant-2'],
      'pcztB64': 'AQID',
      'pcztHash': 'pczt-hash',
      'needsSaplingParams': false,
      'amountZatoshi': '1000',
      'feeZatoshi': '100',
      'recipientAddress': 'u1recipient',
      'addressType': 'unified',
      'createdAt': 42,
    }),
    createdAt: BigInt.from(43),
  );
}

Exception _structuredConflict(String message) {
  return Exception(
    jsonEncode({
      'marker': 'zcash_wallet_multisig_error_v1',
      'kind': 'conflict',
      'message': message,
      'httpStatus': 409,
      'retryable': true,
    }),
  );
}
