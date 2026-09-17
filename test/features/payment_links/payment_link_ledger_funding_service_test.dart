import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signed_operation_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import '../../support/ledger_gift_card_support.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_ledger_funding_service.dart';

void main() {
  test(
    'funding persistence precedes acknowledgement and destructive drain',
    () async {
      final h = LedgerGiftHarness();
      final draft = await h.prepare();
      h.storage.writeGate = Completer<void>();
      final submitted = h.submit(draft);
      await Future<void>.delayed(Duration.zero);
      expect(h.operations.broadcasts, 1);
      expect(h.operations.acks, 0);
      var drained = false;
      final drain = h.lifecycle.quiesceAndDrain().then((_) => drained = true);
      await Future<void>.delayed(Duration.zero);
      expect(drained, false);
      h.storage.writeGate!.complete();
      expect((await submitted).fundingMetadataSaved, true);
      await drain;
      expect(h.operations.acks, 1);
      expect(
        (await h.recovery.load()).single.state,
        PaymentLinkRecoveryState.funded,
      );
      expect(h.releases, 1);
    },
  );

  test(
    'storage failure preserves outbox; restart completes without signing or broadcasting again',
    () async {
      final h = LedgerGiftHarness();
      final draft = await h.prepare();
      h.storage.failWrites = true;
      await expectLater(h.submit(draft), throwsStateError);
      expect(h.operations.acks, 0);
      expect(h.operations.entry!.state, 'result_pending_ack');
      h.storage.failWrites = false;
      final entry = h.operations.entry!;
      await h.service.complete(
        entry,
        LedgerSignedOperationBroadcastResult(
          operationId: entry.operationId,
          txid: 'gift-txid',
          status: 'broadcasted',
          requiresAck: true,
        ),
      );
      expect(h.operations.acks, 1);
      expect(h.operations.broadcasts, 1);
      expect(h.operations.checkpoints, 1);
      expect(
        (await h.recovery.load()).single.state,
        PaymentLinkRecoveryState.funded,
      );
    },
  );

  test(
    'shared recovery stays shared and mismatched result is not acknowledged',
    () async {
      final h = LedgerGiftHarness();
      final draft = await h.prepare();
      await h.operations.checkpoint(
        operationId: h.service.operationId('account-1', ledgerGiftLink.address),
        accountUuid: 'account-1',
        kind: LedgerSignedOperationKind.giftCard,
        externalRef: draft.link.address,
        pcztWithProofsBytes: [2],
        pcztWithSignaturesBytes: [3],
      );
      final entry = h.operations.entry!;
      await h.recovery.markFunded(
        address: draft.link.address,
        fundingTxids: 'gift-txid',
      );
      await h.recovery.markShared(address: draft.link.address);
      await expectLater(
        h.service.complete(
          entry,
          LedgerSignedOperationBroadcastResult(
            operationId: entry.operationId,
            txid: 'wrong-txid',
            status: 'broadcasted',
            requiresAck: true,
          ),
        ),
        throwsStateError,
      );
      expect(h.operations.acks, 0);
      await h.service.complete(
        entry,
        LedgerSignedOperationBroadcastResult(
          operationId: entry.operationId,
          txid: 'gift-txid',
          status: 'broadcasted',
          requiresAck: true,
        ),
      );
      expect(h.operations.acks, 1);
      expect(
        (await h.recovery.load()).single.state,
        PaymentLinkRecoveryState.shared,
      );
    },
  );

  test(
    'expired transaction removes unfunded secret before acknowledging',
    () async {
      final h = LedgerGiftHarness();
      final draft = await h.prepare();
      h.operations.status = 'expired';
      await expectLater(
        h.submit(draft),
        throwsA(isA<LedgerGiftFundingTerminalException>()),
      );
      expect(await h.recovery.load(), isEmpty);
      expect(h.operations.acks, 1);
    },
  );

  test(
    'definitively rejected gift transaction removes only unbroadcast draft',
    () async {
      final h = LedgerGiftHarness();
      final draft = await h.prepare();
      h.operations.terminalRejection = true;
      await expectLater(
        h.submit(draft),
        throwsA(isA<LedgerGiftFundingTerminalException>()),
      );
      expect(await h.recovery.load(), isEmpty);
      expect(h.operations.entry, isNull);
      expect(h.operations.acks, 0);
    },
  );

  test(
    'input reservation remains held through broadcast and uncertain settlement',
    () async {
      final h = LedgerGiftHarness();
      final draft = await h.prepare();
      h.operations.status = 'broadcast_unknown';
      h.operations.broadcastGate = Completer<void>();
      final submitted = h.submit(draft);
      await Future<void>.delayed(Duration.zero);
      expect(h.operations.broadcasts, 1);
      expect(h.settlements, isEmpty);
      h.operations.broadcastGate!.complete();
      await submitted;
      expect(h.settlements, ['broadcast_unknown']);
      expect(h.releases, 0);
      expect(h.operations.acks, 1);
    },
  );

  test('deleted account cannot checkpoint a late device signature', () async {
    final h = LedgerGiftHarness();
    final draft = await h.prepare();
    h.accountExists = false;
    await expectLater(h.submit(draft), throwsStateError);
    expect(h.operations.checkpoints, 0);
  });
}
