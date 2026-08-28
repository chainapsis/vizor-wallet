import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_immediate_migration_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_signing_modal.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('signs and completes one Immediate migration PCZT', () async {
    final completedMessages = <rust_sync.KeystoneSignedMigrationMessage>[];
    final phases = <LedgerSigningModalPhase>[];
    var discarded = false;
    final service = LedgerImmediateMigrationService(
      prepare: ({required accountUuid, required approvedPlan}) async {
        expect(accountUuid, 'ledger-account');
        expect(approvedPlan, same(_plan));
        return _request(expectedSignatureCount: 2);
      },
      signPczt: (accountUuid, pcztBytes) async {
        expect(accountUuid, 'ledger-account');
        expect(pcztBytes, [1, 2, 3]);
        return const [
          LedgerVotingSignature(
            pool: 0,
            actionIndex: 0,
            signature: _signatureA,
          ),
          LedgerVotingSignature(
            pool: 0,
            actionIndex: 1,
            signature: _signatureB,
          ),
        ];
      },
      loadProofStatus: ({required requestId}) async {
        expect(requestId, 'immediate-request');
        return _proofStatus(isReady: true);
      },
      complete:
          ({
            required accountUuid,
            required requestId,
            required signedMessages,
          }) async {
            expect(accountUuid, 'ledger-account');
            expect(requestId, 'immediate-request');
            completedMessages.addAll(signedMessages);
            return _result;
          },
      discard: ({required accountUuid, required requestId}) async {
        discarded = true;
      },
    );

    final result = await service.migrate(
      accountUuid: 'ledger-account',
      approvedPlan: _plan,
      cancellation: LedgerImmediateMigrationCancellation(),
      onPhaseChanged: phases.add,
    );

    expect(result, same(_result));
    expect(discarded, isFalse);
    expect(phases, [
      LedgerSigningModalPhase.preparing,
      LedgerSigningModalPhase.awaitingDevice,
      LedgerSigningModalPhase.broadcasting,
    ]);
    expect(completedMessages, hasLength(1));
    expect(completedMessages.single.id, 'immediate-message');
    expect(completedMessages.single.sigs, hasLength(2));
    expect(completedMessages.single.sigs[0].pool, 0);
    expect(completedMessages.single.sigs[0].actionIndex, 0);
    expect(
      completedMessages.single.sigs[0].sig,
      Uint8List.fromList(_signatureA),
    );
    expect(completedMessages.single.sigs[1].actionIndex, 1);
  });

  test(
    'discards the request when Ledger returns the wrong signature count',
    () async {
      var completed = false;
      var discardedRequestId = '';
      final service = LedgerImmediateMigrationService(
        prepare: ({required accountUuid, required approvedPlan}) async =>
            _request(expectedSignatureCount: 2),
        signPczt: (_, _) async => const [
          LedgerVotingSignature(
            pool: 0,
            actionIndex: 0,
            signature: _signatureA,
          ),
        ],
        loadProofStatus: ({required requestId}) async =>
            _proofStatus(isReady: true),
        complete:
            ({
              required accountUuid,
              required requestId,
              required signedMessages,
            }) async {
              completed = true;
              return _result;
            },
        discard: ({required accountUuid, required requestId}) async {
          discardedRequestId = requestId;
        },
      );

      await expectLater(
        service.migrate(
          accountUuid: 'ledger-account',
          approvedPlan: _plan,
          cancellation: LedgerImmediateMigrationCancellation(),
          onPhaseChanged: (_) {},
        ),
        throwsA(isA<StateError>()),
      );

      expect(completed, isFalse);
      expect(discardedRequestId, 'immediate-request');
    },
  );

  test('discards the request when proof preparation fails', () async {
    var discarded = false;
    final service = LedgerImmediateMigrationService(
      prepare: ({required accountUuid, required approvedPlan}) async =>
          _request(expectedSignatureCount: 1),
      signPczt: (_, _) async => const [
        LedgerVotingSignature(pool: 0, actionIndex: 0, signature: _signatureA),
      ],
      loadProofStatus: ({required requestId}) async =>
          _proofStatus(isFailed: true, message: 'proof worker failed'),
      complete:
          ({
            required accountUuid,
            required requestId,
            required signedMessages,
          }) async => _result,
      discard: ({required accountUuid, required requestId}) async {
        discarded = true;
      },
    );

    await expectLater(
      service.migrate(
        accountUuid: 'ledger-account',
        approvedPlan: _plan,
        cancellation: LedgerImmediateMigrationCancellation(),
        onPhaseChanged: (_) {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(discarded, isTrue);
  });
}

final _plan = rust_sync.OrchardMigrationImmediatePlan(
  totalInputZatoshi: BigInt.from(10_000_000),
  feeZatoshi: BigInt.from(10_000),
  migratedZatoshi: BigInt.from(9_990_000),
  inputNoteCount: 2,
);

final _result = rust_sync.IronwoodMigrationResult(
  txids: 'txid',
  status: 'broadcasting',
  broadcastedCount: 1,
  totalCount: 1,
  feeZatoshi: BigInt.from(10_000),
  migratedZatoshi: BigInt.from(9_990_000),
);

rust_sync.KeystoneMigrationSigningRequest _request({
  required int expectedSignatureCount,
}) {
  return rust_sync.KeystoneMigrationSigningRequest(
    requestId: 'immediate-request',
    messages: [
      rust_sync.KeystoneMigrationMessage(
        id: 'immediate-message',
        redactedPczt: Uint8List.fromList([1, 2, 3]),
        expectedSignatureCount: expectedSignatureCount,
      ),
    ],
    signingBatchLimit: 1,
  );
}

rust_sync.KeystoneMigrationProofStatus _proofStatus({
  bool isReady = false,
  bool isFailed = false,
  String? message,
}) {
  return rust_sync.KeystoneMigrationProofStatus(
    readyCount: isReady ? 1 : 0,
    totalCount: 1,
    isReady: isReady,
    isFailed: isFailed,
    message: message,
  );
}

const _signatureA = <int>[
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
  1,
];
const _signatureB = <int>[
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
  2,
];
