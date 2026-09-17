import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_ledger_signing_overlay.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import '../../support/ledger_gift_card_support.dart';
import '../../support/payment_links_screen_support.dart';

void main() {
  setUpAll(loadPaymentLinksTestFonts);
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
      'Vizor built a gift card request that the Zcash app on your Ledger could not accept. Go back and create a new gift card. Nothing was sent.',
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
