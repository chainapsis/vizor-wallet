import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_ledger_completion_service.dart';

const _partial = LedgerSignedOperationBroadcastResult(
  operationId: 'operation-1',
  txid: 'mined-parent,expired-child',
  status: 'partial_broadcast',
  message: 'The remaining round expired',
  requiresAck: true,
);

SwapIntent _intent(bool payMode) => SwapIntent(
  id: 'intent-1',
  pair: 'ZEC -> USDC',
  sellAmount: '1 ZEC',
  receiveEstimate: '70 USDC',
  provider: 'NEAR Intents',
  status: SwapIntentStatus.awaitingDeposit,
  nextAction: 'Send deposit',
  accountUuid: 'account-1',
  payMode: payMode,
);

void main() {
  for (final status in [
    'broadcasted',
    'broadcast_unknown',
    'broadcasted_storage_failed',
    'partial_broadcast',
  ]) {
    test('$status is accepted for Ledger result persistence', () {
      expect(
        classifyLedgerDepositBroadcastResult(
          LedgerSignedOperationBroadcastResult(
            operationId: 'operation-1',
            txid: 'txid-1',
            status: status,
            requiresAck: true,
          ),
        ),
        LedgerDepositBroadcastDisposition.accepted,
      );
    });
  }

  for (final status in ['partial_broadcast', 'pending_broadcast', 'unknown']) {
    test('$status with an empty txid is invalid', () {
      expect(
        classifyLedgerDepositBroadcastResult(
          LedgerSignedOperationBroadcastResult(
            operationId: 'operation-1',
            txid: ' ',
            status: status,
            requiresAck: true,
          ),
        ),
        LedgerDepositBroadcastDisposition.invalid,
      );
    });
  }

  test('expired remains terminal and partial remains uncertain', () {
    expect(
      classifyLedgerDepositBroadcastResult(
        const LedgerSignedOperationBroadcastResult(
          operationId: 'operation-1',
          txid: 'computed-txid',
          status: 'expired',
          requiresAck: true,
        ),
      ),
      LedgerDepositBroadcastDisposition.expired,
    );
    expect(
      const SwapDepositBroadcastResult(
        txHash: 'txid-1',
        status: 'partial_broadcast',
      ).isCertain,
      isFalse,
    );
  });

  for (final payMode in [false, true]) {
    test(
      'partial completion persists ${payMode ? 'pay' : 'swap'} metadata before ack',
      () async {
        final operations = _Operations();
        final writing = Completer<void>();
        final gate = Completer<void>();
        final service = SwapLedgerCompletionService(
          lifecycle: LedgerOperationLifecycle(),
          operations: operations,
          accountExists: (uuid) => uuid == 'account-1',
          persist: (intent, broadcast) async {
            expect(intent.id, 'intent-1');
            expect(intent.payMode, payMode);
            expect(broadcast.txHash, _partial.txid);
            expect(broadcast.status, _partial.status);
            expect(broadcast.message, _partial.message);
            expect(broadcast.isCertain, isFalse);
            writing.complete();
            await gate.future;
          },
        );
        final completion = service.complete(_intent(payMode), _partial);
        // Observe a rejection without allowing an unhandled future error.
        final observed = completion.then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
        await Future.any([writing.future, observed]);
        expect(writing.isCompleted, isTrue);
        expect(operations.acknowledged, isEmpty);
        gate.complete();
        expect(await observed, isNull);
        expect(operations.acknowledged, ['operation-1']);
      },
    );
  }

  test(
    'failed partial persistence keeps the result available for retry',
    () async {
      final operations = _Operations();
      var writes = 0;
      final service = SwapLedgerCompletionService(
        lifecycle: LedgerOperationLifecycle(),
        operations: operations,
        accountExists: (_) => true,
        persist: (_, broadcast) async {
          writes++;
          expect(broadcast.status, 'partial_broadcast');
          if (writes == 1) throw StateError('storage unavailable');
        },
      );
      await expectLater(
        service.complete(_intent(false), _partial),
        throwsStateError,
      );
      expect(writes, 1);
      expect(operations.acknowledged, isEmpty);
      await service.complete(_intent(false), _partial);
      expect(writes, 2);
      expect(operations.acknowledged, ['operation-1']);
    },
  );

  test(
    'partial completion cannot persist or acknowledge a deleted account',
    () async {
      final operations = _Operations();
      var writes = 0;
      final service = SwapLedgerCompletionService(
        lifecycle: LedgerOperationLifecycle(),
        operations: operations,
        accountExists: (_) => false,
        persist: (_, _) async => writes++,
      );
      await expectLater(
        service.complete(_intent(false), _partial),
        throwsStateError,
      );
      expect(writes, 0);
      expect(operations.acknowledged, isEmpty);
    },
  );
}

class _Operations implements LedgerSignedOperationService {
  final acknowledged = <String>[];

  @override
  Future<void> acknowledge(String operationId) async =>
      acknowledged.add(operationId);

  @override
  Future<List<LedgerSignedOperationMetadata>> list() =>
      throw UnimplementedError();

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) => throw UnimplementedError();

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) => throw UnimplementedError();
}
