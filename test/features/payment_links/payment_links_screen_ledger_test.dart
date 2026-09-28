import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_ledger_signing_overlay.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import '../../support/ledger_gift_card_support.dart';
import '../../support/payment_links_screen_support.dart';

void main() {
  setUpAll(loadPaymentLinksTestFonts);

  testWidgets(
    'desktop Ledger creates a two-card batch with one signing request',
    (tester) async {
      final h = LedgerGiftHarness();
      final batch = _LedgerBatchOperations();
      final signature = Completer<List<int>>();
      await pumpPaymentLinksScreen(
        tester,
        bootstrap: ledgerGiftBootstrap,
        operations: _StoreBackedOperations(h.recovery),
        batchOperations: batch,
        ledgerFunding: h.service,
        recoveryStore: h.recovery,
        ledgerSigner: (_, _) => signature.future,
      );
      await tester.tap(
        find.byKey(const ValueKey('payment_link_create_batch_button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_bulk_amount')),
        '0.1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 2 cards'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create 2 cards'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PaymentLinkLedgerSigningOverlay), findsOneWidget);
      expect(find.text('Check your Ledger'), findsOneWidget);
      signature.complete([3]);
      await tester.pumpAndSettle();
      expect(h.operations.checkpoints, 1);
      expect(batch.fundCalls, 0);
      expect(find.text('Save all links as CSV'), findsOneWidget);
    },
  );

  testWidgets('Ledger batch cancellation refreshes the review quote', (
    tester,
  ) async {
    final h = LedgerGiftHarness();
    final batch = _LedgerBatchOperations();
    final signature = Completer<List<int>>();
    await pumpPaymentLinksScreen(
      tester,
      bootstrap: ledgerGiftBootstrap,
      batchOperations: batch,
      ledgerFunding: h.service,
      recoveryStore: h.recovery,
      ledgerSigner: (_, _) => signature.future,
    );
    await tester.tap(
      find.byKey(const ValueKey('payment_link_create_batch_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_bulk_amount')),
      '0.1',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review 2 cards'));
    await tester.pumpAndSettle();
    expect(batch.prepareCalls, 1);
    expect(find.text('0.2004 ZEC'), findsOneWidget);

    await tester.tap(find.text('Create 2 cards'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(PaymentLinkLedgerSigningOverlay), findsOneWidget);
    await tester.tap(find.text('Back to gift card'));
    await tester.pump();
    signature.complete([3]);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(PaymentLinkLedgerSigningOverlay).evaluate().isEmpty &&
          batch.prepareCalls == 2) {
        break;
      }
    }

    expect(h.hardware.discards, 1);
    expect(await h.recovery.load(), isEmpty);
    expect(find.byType(PaymentLinkLedgerSigningOverlay), findsNothing);
    expect(batch.prepareCalls, 2);
    expect(find.text('0.2005 ZEC'), findsOneWidget);
    expect(find.text('Create 2 cards'), findsOneWidget);
  });

  for (final outcome in ['funded', 'cancelled', 'expired']) {
    final cancel = outcome == 'cancelled';
    testWidgets('desktop Ledger Gift Card $outcome', (tester) async {
      final h = LedgerGiftHarness();
      if (outcome == 'expired') h.operations.status = 'expired';
      final signature = Completer<List<int>>();
      await _openLedgerSigning(tester, h, signature);
      expect(find.text('Check your Ledger'), findsOneWidget);
      expect(find.text('Sign gift card on Keystone'), findsNothing);
      if (cancel) {
        await tester.tap(find.text('Back to gift card'));
        await tester.pump();
        signature.complete([3]);
        await tester.pumpAndSettle();
        expect(h.operations.checkpoints, 0);
        expect(h.hardware.discards, 1);
        expect(await h.recovery.load(), isEmpty);
      } else if (outcome == 'expired') {
        signature.complete([3]);
        await tester.pumpAndSettle();
        expect(h.operations.acks, 1);
        expect(find.text('Try again'), findsNothing);
        expect(await h.recovery.load(), isEmpty);
        await tester.tap(find.text('Back to gift card'));
        await tester.pumpAndSettle();
      } else {
        signature.complete([3]);
        await tester.pumpAndSettle();
        expect(h.operations.acks, 1);
        expect(
          (await h.recovery.load()).single.state,
          PaymentLinkRecoveryState.funded,
        );
      }
      expect(find.byType(PaymentLinkLedgerSigningOverlay), findsNothing);
    });
  }

  for (final (status, message, canRetry) in const [
    ('6985', 'The gift card funding was rejected on your Ledger.', true),
    (
      '6a80',
      'Your Ledger couldn’t accept this request. Create a new gift card. Nothing was sent.',
      false,
    ),
  ]) {
    testWidgets('desktop Ledger Gift Card status 0x$status', (tester) async {
      final h = LedgerGiftHarness();
      final signature = Completer<List<int>>();
      await _openLedgerSigning(tester, h, signature);

      signature.completeError(
        StateError('ledger_status_$status: test fixture'),
      );
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('ledger_status_'), findsNothing);
      expect(find.text('Try again'), canRetry ? findsOneWidget : findsNothing);
      expect(h.operations.checkpoints, 0);
      await tester.tap(find.text('Back to gift card'));
      await tester.pumpAndSettle();
      expect(h.hardware.discards, 1);
      expect(find.byType(PaymentLinkLedgerSigningOverlay), findsNothing);
    });
  }
}

class _LedgerBatchOperations implements PaymentLinkBatchOperations {
  int fundCalls = 0;
  int prepareCalls = 0;

  @override
  Future<PaymentLinkBatchDraft> prepareBatch({
    required int count,
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    required PaymentLinkPresentation presentation,
    List<String>? artworkIds,
  }) async {
    prepareCalls++;
    final second = VizorPaymentLink(
      label: ledgerGiftLink.label,
      network: ledgerGiftLink.network,
      address: 'u1giftsecond',
      amountZatoshi: amountZatoshi,
      mnemonic: ledgerGiftLink.mnemonic,
      birthdayHeight: ledgerGiftLink.birthdayHeight,
      createdAt: ledgerGiftLink.createdAt,
      presentation: presentation,
    );
    final first = VizorPaymentLink(
      label: ledgerGiftLink.label,
      network: ledgerGiftLink.network,
      address: ledgerGiftLink.address,
      amountZatoshi: amountZatoshi,
      mnemonic: ledgerGiftLink.mnemonic,
      birthdayHeight: ledgerGiftLink.birthdayHeight,
      createdAt: ledgerGiftLink.createdAt,
      presentation: presentation,
    );
    return PaymentLinkBatchDraft(
      id: 'ledger-screen-batch',
      links: [first, second],
      quote: PaymentLinkBatchQuote(
        sourceAccountUuid: sourceAccountUuid,
        count: count,
        recipientAmountZatoshi: amountZatoshi,
        fundingFeeZatoshi: BigInt.from(prepareCalls == 1 ? 20000 : 30000),
      ),
    );
  }

  @override
  Future<PaymentLinkBatchFundingResult> fundBatch(
    PaymentLinkBatchDraft draft,
  ) async {
    fundCalls++;
    throw StateError('Hardware batch must use device signing.');
  }

  @override
  Future<void> abandonUnsubmittedBatch(String batchId) async {}

  @override
  Future<void> retryBatchFundingMetadata({
    required String batchId,
    required String fundingTxids,
  }) async {}
}

Future<void> _openLedgerSigning(
  WidgetTester tester,
  LedgerGiftHarness h,
  Completer<List<int>> signature,
) async {
  await pumpPaymentLinksScreen(
    tester,
    bootstrap: ledgerGiftBootstrap,
    ledgerFunding: h.service,
    ledgerSigner: (_, _) => signature.future,
  );
  await tester.tap(find.text('Create new card'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('payment_link_amount_editor')),
    '0.1',
  );
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('payment_link_amount_continue_button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip message'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create card'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(PaymentLinkLedgerSigningOverlay), findsOneWidget);
}

/// Lists the cards the Ledger harness actually saved, as the app's own
/// operations do with the shared recovery store.
class _StoreBackedOperations extends FakePaymentLinkOperations {
  _StoreBackedOperations(this.store);

  final PaymentLinkRecoveryStore store;

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() =>
      store.load();
}
