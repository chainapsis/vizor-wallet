import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_account_material_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_coordinator_service.dart';
import 'package:zcash_wallet/src/providers/multisig_pending_session_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_realtime_cursor_store.dart';
import 'package:zcash_wallet/src/providers/multisig_signing_request_provider.dart';
import 'package:zcash_wallet/src/providers/multisig_vault_label_store.dart';
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

  test('retries round submission after unauthorized advance detail', () async {
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
      failRound1UnauthorizedOnce: true,
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

    expect(coordinator.refreshCalls, ['session-1|participant-1|refresh-token']);
    expect(coordinator.round1AccessTokens, ['access-token', 'new-access']);
    expect(updated.round1ParticipantIds, ['participant-1']);
    expect(updated.localRound1Submitted, isTrue);
  });

  test('submitRound2 requires local Round 1 signing state', () async {
    final requestStore = _FakeSigningRequestStore()
      ..records = [
        _submittedRecord(signingRequestId: 'signing-request').copyWith(
          localStateJson: jsonEncode({'round1_sent': false}),
          round1ParticipantIds: const ['participant-1', 'participant-2'],
        ),
      ];
    final materialStore = _FakeAccountMaterialStore()
      ..put(
        _accountMaterial(
          localBackupCompletedAt: 10,
          accessTokenExpiresAt: 9999999999,
        ),
      );
    final coordinator = _FakeCoordinatorService();
    final container = _container(
      requestStore: requestStore,
      materialStore: materialStore,
      coordinatorService: coordinator,
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(multisigSigningRequestsProvider.notifier)
          .submitRound2(requestStore.records.single),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Submit Round 1 before Round 2.',
        ),
      ),
    );

    expect(coordinator.round2Calls, isEmpty);
  });

  test('aggregateSignedPczt can recover without local Round 2 state', () async {
    final requestStore = _FakeSigningRequestStore()
      ..records = [
        _submittedRecord(signingRequestId: 'signing-request').copyWith(
          round1ParticipantIds: const ['participant-1', 'participant-2'],
          round2ParticipantIds: const ['participant-1', 'participant-2'],
        ),
      ];
    final materialStore = _FakeAccountMaterialStore()
      ..put(
        _accountMaterial(
          localBackupCompletedAt: 10,
          accessTokenExpiresAt: 9999999999,
        ),
      );
    final coordinator = _FakeCoordinatorService();
    final container = _container(
      requestStore: requestStore,
      materialStore: materialStore,
      coordinatorService: coordinator,
    );
    addTearDown(container.dispose);

    final updated = await container
        .read(multisigSigningRequestsProvider.notifier)
        .aggregateSignedPczt(requestStore.records.single);

    expect(coordinator.aggregateCalls, ['signing-request|participant-1']);
    expect(updated.signedPcztB64, 'BAUG');
    expect(updated.localStateJson, '{"signed_pczt_b64":true}');
  });

  test('refreshForAccount catches up from stored inbox cursor', () async {
    final requestStore = _FakeSigningRequestStore();
    final materialStore = _FakeAccountMaterialStore()
      ..put(_accountMaterial(accessTokenExpiresAt: 9999999999));
    final cursorStore = _FakeRealtimeCursorStore()
      ..cursors['session-1:participant-1'] = const MultisigRealtimeCursor(
        inboxCursor: 5,
      );
    final coordinator = _FakeCoordinatorService(
      inboxCursor: 8,
      inboxMessages: [_txRequestMessage(signingRequestId: 'signing-request')],
    );
    final container = _container(
      requestStore: requestStore,
      materialStore: materialStore,
      coordinatorService: coordinator,
      cursorStore: cursorStore,
    );
    addTearDown(container.dispose);

    await container
        .read(multisigSigningRequestsProvider.notifier)
        .refreshForAccount('account-1');

    expect(coordinator.inboxCalls, ['session-1|participant-1|5']);
    expect(requestStore.records.single.signingRequestId, 'signing-request');
    expect(cursorStore.cursors['session-1:participant-1']?.inboxCursor, 8);
  });

  test(
    'refreshForAccount does not advance cursor when inbox fetch fails',
    () async {
      final materialStore = _FakeAccountMaterialStore()
        ..put(_accountMaterial(accessTokenExpiresAt: 9999999999));
      final cursorStore = _FakeRealtimeCursorStore()
        ..cursors['session-1:participant-1'] = const MultisigRealtimeCursor(
          inboxCursor: 5,
        );
      final coordinator = _FakeCoordinatorService(
        inboxError: StateError('network down'),
      );
      final container = _container(
        materialStore: materialStore,
        coordinatorService: coordinator,
        cursorStore: cursorStore,
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(multisigSigningRequestsProvider.notifier)
            .refreshForAccount('account-1'),
        throwsA(anything),
      );

      expect(coordinator.inboxCalls, ['session-1|participant-1|5']);
      expect(cursorStore.cursors['session-1:participant-1']?.inboxCursor, 5);
    },
  );

  test('deletes draft records for a removed account', () async {
    final requestStore = _FakeSigningRequestStore()
      ..records = [
        _record(accountUuid: 'account-1', sendFlowId: 'flow-1'),
        _record(accountUuid: 'account-2', sendFlowId: 'flow-2'),
      ];
    final cursorStore = _FakeRealtimeCursorStore()
      ..cursors['session-1:participant-1'] = const MultisigRealtimeCursor(
        inboxCursor: 5,
      );
    final container = _container(
      requestStore: requestStore,
      cursorStore: cursorStore,
    );
    addTearDown(container.dispose);

    await container
        .read(multisigSigningRequestsProvider.notifier)
        .deleteForAccount('account-1');

    expect(requestStore.records.map((record) => record.accountUuid), [
      'account-2',
    ]);
    expect(cursorStore.cursors.containsKey('session-1:participant-1'), isFalse);
  });

  test(
    'deleteForAccount clears cursor from material without records',
    () async {
      final requestStore = _FakeSigningRequestStore();
      final materialStore = _FakeAccountMaterialStore()
        ..put(_accountMaterial());
      final cursorStore = _FakeRealtimeCursorStore()
        ..cursors['session-1:participant-1'] = const MultisigRealtimeCursor(
          inboxCursor: 5,
        );
      final container = _container(
        requestStore: requestStore,
        materialStore: materialStore,
        cursorStore: cursorStore,
      );
      addTearDown(container.dispose);

      await container
          .read(multisigSigningRequestsProvider.notifier)
          .deleteForAccount('account-1');

      expect(requestStore.records, isEmpty);
      expect(
        cursorStore.cursors.containsKey('session-1:participant-1'),
        isFalse,
      );
    },
  );

  test(
    'inbox refresh skips a malformed message and still applies the rest',
    () async {
      final requestStore = _FakeSigningRequestStore();
      final materialStore = _FakeAccountMaterialStore()
        ..put(_accountMaterial(accessTokenExpiresAt: 9999999999));
      final cursorStore = _FakeRealtimeCursorStore();
      final malformed = rust_multisig.ApiMultisigSigningMessage(
        cursor: 1,
        messageId: 'message-bad',
        sessionId: 'session-1',
        kind: 'tx_request',
        fromParticipantId: 'participant-2',
        toParticipantId: 'participant-1',
        relatedId: 'other-request',
        plaintextJson: 'not json {',
        createdAt: BigInt.from(41),
      );
      final coordinator = _FakeCoordinatorService(
        inboxCursor: 9,
        inboxMessages: [
          malformed,
          _txRequestMessage(signingRequestId: 'signing-request'),
        ],
      );
      final container = _container(
        requestStore: requestStore,
        materialStore: materialStore,
        coordinatorService: coordinator,
        cursorStore: cursorStore,
      );
      addTearDown(container.dispose);

      // A malformed message must not abort the refresh: the cursor would
      // never advance past it and the inbox would be stuck forever.
      await container
          .read(multisigSigningRequestsProvider.notifier)
          .refreshForAccount('account-1');

      expect(requestStore.records.single.signingRequestId, 'signing-request');
      expect(cursorStore.cursors['session-1:participant-1']?.inboxCursor, 9);
    },
  );

  test(
    'createRequest keeps the proposal when auth refresh fails after the '
    'PCZT is consumed',
    () async {
      final requestStore = _FakeSigningRequestStore();
      final materialStore = _FakeAccountMaterialStore()
        ..put(_accountMaterial(localBackupCompletedAt: 10));
      final proposalService = _FakeProposalService(
        pcztBytes: Uint8List.fromList([1, 2, 3]),
      );
      final coordinator = _FakeCoordinatorService(failRefreshOnce: true);
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
          needsSaplingParams: false,
        ),
        throwsA(anything),
      );

      // The PCZT was created before the token refresh, so the record must
      // survive the failure and the proposal must not be discarded — a
      // retry continues from the stored record.
      expect(proposalService.discardCalls, isEmpty);
      expect(requestStore.records.single.signingRequestId, 'local_flow-1');

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
        needsSaplingParams: false,
      );

      expect(proposalService.createCalls, hasLength(1));
      expect(submitted.signingRequestId, 'signing-request');
      expect(submitted.coordinatorSubmitted, isTrue);
    },
  );

  test('createRequest retry honors a changed signer selection', () async {
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
        needsSaplingParams: false,
      ),
      throwsA(anything),
    );

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
      selectedParticipantIds: const ['participant-1', 'participant-3'],
      needsSaplingParams: false,
    );

    expect(submitted.selectedParticipantIds, [
      'participant-1',
      'participant-3',
    ]);
  });

  test('inbox vault_label broadcasts land in the vault label store', () async {
    final materialStore = _FakeAccountMaterialStore()
      ..put(_accountMaterial(accessTokenExpiresAt: 9999999999));
    final vaultLabelStore = _FakeVaultLabelStore();
    final coordinator = _FakeCoordinatorService(
      inboxCursor: 3,
      inboxMessages: [
        rust_multisig.ApiMultisigSigningMessage(
          cursor: 1,
          messageId: 'message-label',
          sessionId: 'session-1',
          kind: 'vault_label',
          fromParticipantId: 'participant-2',
          toParticipantId: null,
          relatedId: null,
          plaintextJson: jsonEncode({'version': 1, 'label': 'Signer 2'}),
          createdAt: BigInt.from(41),
        ),
      ],
    );
    final container = _container(
      materialStore: materialStore,
      coordinatorService: coordinator,
      vaultLabelStore: vaultLabelStore,
    );
    addTearDown(container.dispose);

    await container
        .read(multisigSigningRequestsProvider.notifier)
        .refreshForAccount('account-1');

    expect(vaultLabelStore.labels['session-1:participant-1'], {
      'participant-2': 'Signer 2',
    });

    // Post-finalize drafts merge the stored vault label into the display
    // name (the coordinator response carries no readable label anymore).
    final merged = MultisigSigningParticipant.fromApi(
      rust_multisig.ApiMultisigParticipant(
        participantId: 'participant-2',
        label: null,
        admissionPublicKey: 'admission-public-2',
        deliveryPublicKey: 'delivery-public-2',
        joinedAt: BigInt.one,
        dkgCompleted: true,
      ),
      vaultLabel: 'Signer 2',
    );
    expect(merged.displayName, 'Signer 2');
  });

  test(
    'refreshRequestProgress merges coordinator round progress into record',
    () async {
      final record =
          _record(accountUuid: 'account-1', sendFlowId: 'flow-1').copyWith(
            state: 'open',
            selectedParticipantIds: const ['participant-1', 'participant-2'],
          );
      final requestStore = _FakeSigningRequestStore()..records = [record];
      final materialStore = _FakeAccountMaterialStore()
        ..put(
          _accountMaterial(
            localBackupCompletedAt: 10,
            accessTokenExpiresAt: 9999999999,
          ),
        );
      final coordinator = _FakeCoordinatorService(
        signingRequestResponse: rust_multisig.ApiMultisigSigningRequest(
          signingRequestId: record.signingRequestId,
          sessionId: record.sessionId,
          requesterParticipantId: record.requesterParticipantId,
          selectedParticipantIds: record.selectedParticipantIds,
          round1ParticipantIds: const ['participant-1', 'participant-2'],
          round2ParticipantIds: const ['participant-2'],
          broadcastParticipantIds: const <String>[],
          state: 'open',
          createdAt: BigInt.from(42),
          updatedAt: BigInt.from(43),
          pcztHash: record.pcztHash,
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
          .refreshRequestProgress(
            accountUuid: 'account-1',
            signingRequestId: record.signingRequestId,
          );

      expect(coordinator.signingRequestCalls, [record.signingRequestId]);
      expect(updated?.round1ParticipantIds, [
        'participant-1',
        'participant-2',
      ]);
      expect(updated?.round2ParticipantIds, ['participant-2']);
      expect(updated?.round1Complete, isTrue);
      expect(
        requestStore.records.single.round1ParticipantIds,
        ['participant-1', 'participant-2'],
      );
    },
  );
}

ProviderContainer _container({
  _FakeSigningRequestStore? requestStore,
  _FakeAccountMaterialStore? materialStore,
  _FakeProposalService? proposalService,
  _FakeCoordinatorService? coordinatorService,
  _FakeRealtimeCursorStore? cursorStore,
  _FakeVaultLabelStore? vaultLabelStore,
}) {
  return ProviderContainer(
    overrides: [
      appSecurityProvider.overrideWith(() => _FakeAppSecurityNotifier()),
      multisigPendingSessionsProvider.overrideWith(
        () => _FakePendingSessionsNotifier(),
      ),
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
      multisigRealtimeCursorStoreProvider.overrideWithValue(
        cursorStore ?? _FakeRealtimeCursorStore(),
      ),
      multisigVaultLabelStoreProvider.overrideWithValue(
        vaultLabelStore ?? _FakeVaultLabelStore(),
      ),
    ],
  );
}

class _FakeVaultLabelStore implements MultisigVaultLabelStore {
  final labels = <String, Map<String, String>>{};

  @override
  Future<Map<String, String>> read(String storageId) async {
    return labels[storageId] ?? const <String, String>{};
  }

  @override
  Future<void> setLabels(String storageId, Map<String, String> update) async {
    if (update.isEmpty) return;
    labels[storageId] = {...?labels[storageId], ...update};
  }

  @override
  Future<void> clear(String storageId) async {
    labels.remove(storageId);
  }
}

class _FakeAppSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }
}

class _FakePendingSessionsNotifier extends MultisigPendingSessionsNotifier {
  @override
  Future<List<MultisigPendingSession>> build() async {
    return const <MultisigPendingSession>[];
  }

  @override
  Future<void> applyAuthUpdate(
    rust_multisig.ApiMultisigAuthUpdate update,
  ) async {}
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

class _FakeRealtimeCursorStore implements MultisigRealtimeCursorStore {
  final cursors = <String, MultisigRealtimeCursor>{};

  @override
  Future<MultisigRealtimeCursor> read(String storageId) async {
    return cursors[storageId] ?? const MultisigRealtimeCursor();
  }

  @override
  Future<void> write(String storageId, MultisigRealtimeCursor cursor) async {
    cursors[storageId] = cursor;
  }

  @override
  Future<void> advanceInboxCursor(String storageId, int cursor) async {
    final current = await read(storageId);
    if (cursor <= current.inboxCursor) return;
    await write(storageId, current.copyWith(inboxCursor: cursor));
  }

  @override
  Future<void> advanceEventsCursor(String storageId, int cursor) async {
    final current = await read(storageId);
    if (cursor <= current.eventsCursor) return;
    await write(storageId, current.copyWith(eventsCursor: cursor));
  }

  @override
  Future<void> clear(String storageId) async {
    cursors.remove(storageId);
  }

  @override
  Future<void> clearAll() async {
    cursors.clear();
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
    this.failRefreshOnce = false,
    this.submitPreparedError,
    this.inboxMessages = const <rust_multisig.ApiMultisigSigningMessage>[],
    this.inboxCursor = 0,
    this.inboxError,
    this.round1Response,
    this.signingRequestResponse,
    this.failRound1UnauthorizedOnce = false,
  });

  bool failPrepareOnce;
  bool failRefreshOnce;
  bool failRound1UnauthorizedOnce;
  final Object? submitPreparedError;
  final List<rust_multisig.ApiMultisigSigningMessage> inboxMessages;
  final int inboxCursor;
  final Object? inboxError;
  final rust_multisig.ApiMultisigSigningAdvance? round1Response;
  final rust_multisig.ApiMultisigSigningRequest? signingRequestResponse;
  final signingRequestCalls = <String>[];
  final prepareCalls = <String>[];
  final submitCalls = <String>[];
  final inboxCalls = <String>[];
  final round1Calls = <String>[];
  final round1AccessTokens = <String>[];
  final round2Calls = <String>[];
  final aggregateCalls = <String>[];
  final refreshCalls = <String>[];

  @override
  Future<rust_multisig.ApiMultisigAuthUpdate> refreshOrResumeAuth({
    required String coordinatorUrl,
    required String sessionId,
    required String participantId,
    required String refreshToken,
    required String admissionSecretKey,
    required String deliverySecretKey,
  }) async {
    refreshCalls.add('$sessionId|$participantId|$refreshToken');
    if (failRefreshOnce) {
      failRefreshOnce = false;
      throw StateError('refresh network down');
    }
    return rust_multisig.ApiMultisigAuthUpdate(
      sessionId: 'session-1',
      participantId: 'participant-1',
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
      admissionPublicKey: 'new-admission-public',
      deliverySecretKey: 'new-delivery-secret',
      deliveryPublicKey: 'new-delivery-public',
      accessTokenExpiresAt: BigInt.from(9999999999),
      refreshTokenExpiresAt: BigInt.from(9999999999),
      resumed: false,
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
      round1ParticipantIds: const <String>[],
      round2ParticipantIds: const <String>[],
      broadcastParticipantIds: const <String>[],
      state: 'open',
      createdAt: BigInt.from(42),
      updatedAt: BigInt.from(43),
      pcztHash: pcztHash,
    );
  }

  @override
  Future<rust_multisig.ApiMultisigSigningRequest> getSigningRequest({
    required String coordinatorUrl,
    required String signingRequestId,
    required String accessToken,
    required String pcztHash,
  }) async {
    signingRequestCalls.add(signingRequestId);
    final response = signingRequestResponse;
    if (response != null) return response;
    return rust_multisig.ApiMultisigSigningRequest(
      signingRequestId: signingRequestId,
      sessionId: 'session-1',
      requesterParticipantId: 'participant-1',
      selectedParticipantIds: const ['participant-1', 'participant-2'],
      round1ParticipantIds: const <String>[],
      round2ParticipantIds: const <String>[],
      broadcastParticipantIds: const <String>[],
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
    String? groupPublicPackageJson,
    required int after,
  }) async {
    inboxCalls.add('$sessionId|$participantId|$after');
    final error = inboxError;
    if (error != null) throw error;
    return rust_multisig.ApiMultisigSigningInbox(
      cursor: inboxCursor,
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
    round1AccessTokens.add(accessToken);
    if (failRound1UnauthorizedOnce && accessToken == 'access-token') {
      failRound1UnauthorizedOnce = false;
      return rust_multisig.ApiMultisigSigningAdvance(
        localStateJson: '{"round1_sent":false}',
        detail:
            'Network error while submitting Round 1: ${_structuredError('unauthorized', 'access token expired', 401)}',
        submitted: false,
      );
    }
    return round1Response ??
        const rust_multisig.ApiMultisigSigningAdvance(
          localStateJson: '{"round1_sent":true}',
          detail: 'Round 1 submitted.',
          submitted: true,
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
  }) async {
    round2Calls.add('$signingRequestId|$participantId');
    return const rust_multisig.ApiMultisigSigningAdvance(
      localStateJson: '{"round2_sent":true}',
      detail: 'Round 2 submitted.',
      submitted: true,
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
  }) async {
    aggregateCalls.add('$signingRequestId|$participantId');
    return rust_multisig.ApiMultisigSignedPczt(
      localStateJson: '{"signed_pczt_b64":true}',
      signedPcztBytes: Uint8List.fromList([4, 5, 6]),
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
  return Exception(_structuredError('conflict', message, 409));
}

String _structuredError(String kind, String message, int httpStatus) {
  return jsonEncode({
    'marker': 'zcash_wallet_multisig_error_v1',
    'kind': kind,
    'message': message,
    'httpStatus': httpStatus,
    'retryable': true,
  });
}
