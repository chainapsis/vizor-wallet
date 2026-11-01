import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/zcash/block_spacing.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_ledger_funding_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_keystone_signing_overlay.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_ledger_signing_overlay.dart';

import 'ledger_gift_card_support.dart';
import 'payment_links_screen_support.dart';

void registerGiftCardHardwareFeeTransitionChecks({required bool mobile}) {
  setUpAll(loadPaymentLinksTestFonts);

  for (final ledger in [false, true]) {
    for (final quoteFails in [false, true]) {
      testWidgets(
        '${mobile ? 'Mobile' : 'Desktop'} ${ledger ? 'Ledger' : 'Keystone'} '
        'stale single-card quote exits signing '
        '(requote fails=$quoteFails)',
        (tester) async {
          if (mobile) {
            // Window policy reads the view metrics as well as route bounds.
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(393, 852);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
          }
          final hardware = _FeeTransitionHardware();
          final operations = _FeeTransitionOperations(hardware);
          final h = LedgerGiftHarness();
          final signature = Completer<List<int>>();
          var signingRequests = 0;
          final ledgerService = PaymentLinkLedgerFundingService(
            hardware: hardware,
            operations: h.operations,
            recovery: h.recovery,
            lifecycle: h.lifecycle,
            accountExists: (_) => true,
            settleProposal: (_, _) async {},
            refresh: () async {},
          );
          await pumpPaymentLinksScreen(
            tester,
            bootstrap: ledger ? ledgerGiftBootstrap : hardwareBootstrap,
            operations: operations,
            hardwareSigning: hardware,
            ledgerFunding: ledgerService,
            ledgerOperations: h.operations,
            recoveryStore: h.recovery,
            ledgerSigner: (_, _) {
              signingRequests++;
              return signature.future;
            },
            logicalSize: mobile ? const Size(393, 852) : const Size(1080, 720),
            // The display still sees the pre-NU7 epoch throughout this test.
            feeSchedule: const BlockSpacing(
              preNu7BlockSeconds: 75,
              nu7BlockSeconds: 25,
              nu7ActivationHeight: 100000000,
            ),
          );
          await _reviewCard(tester, mobile: mobile);
          expect(find.text('1.0002 ZEC'), findsOneWidget);
          final oldQuoteCount = operations.quotedAccounts.length;
          final create = mobile
              ? find.byKey(
                  const ValueKey('payment_link_mobile_review_continue_button'),
                )
              : find.text('Create card');
          await tester.tap(create);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(hardware.quotes, hasLength(1));
          hardware.nu7 = true;
          operations.failQuote = quoteFails;
          hardware.firstPreparation.complete();
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }

          expect(find.byType(PaymentLinkLedgerSigningOverlay), findsNothing);
          expect(find.byType(PaymentLinkKeystoneSigningOverlay), findsNothing);
          expect(operations.quotedAccounts.length, oldQuoteCount + 1);
          expect(hardware.quotes, hasLength(1));
          expect(signingRequests, 0);
          expect(h.operations.checkpoints, 0);
          expect(h.operations.broadcasts, 0);
          expect(operations.createdAmounts, isEmpty);
          expect(
            find.text(mobile ? 'Approve & create' : 'Card amount'),
            findsOneWidget,
          );

          if (quoteFails) {
            expect(
              find.text(
                'Card fee could not be updated. Return to the amount step and try again.',
              ),
              findsOneWidget,
            );
            // The old quote cannot be signed when the replacement is unknown.
            await tester.tap(create);
            await tester.pumpAndSettle();
            expect(hardware.quotes, hasLength(1));
            return;
          }

          expect(find.text('1.00004 ZEC'), findsOneWidget);
          await tester.tap(create);
          await tester.pump();
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(hardware.quotes, hasLength(2));
          expect(hardware.quotes.last!.fundingFeeZatoshi, BigInt.from(2000));
          expect(
            hardware.quotes.last!.claimFeeReserveZatoshi,
            BigInt.from(2000),
          );
          expect(hardware.createdAmounts, [BigInt.from(100000000)]);
          expect(hardware.createdMessages, ['Keep this message']);
          expect(
            hardware.presentations.last!.artworkId,
            hardware.presentations.first!.artworkId,
          );
          expect(hardware.discardedDrafts, isEmpty);
          expect(h.operations.checkpoints, 0);
          expect(h.operations.broadcasts, 0);
          if (ledger) {
            expect(signingRequests, 1);
            expect(
              find.byType(PaymentLinkLedgerSigningOverlay),
              findsOneWidget,
            );
            if (mobile) {
              await tester.binding.handlePopRoute();
            } else {
              await tester.tap(find.text('Back to gift card'));
            }
            await tester.pump();
            signature.complete([3]);
          } else {
            if (mobile) {
              expect(
                find.byKey(const ValueKey('payment_link_keystone_sign_screen')),
                findsOneWidget,
              );
              await tester.binding.handlePopRoute();
            } else {
              expect(find.text('Sign gift card on Keystone'), findsOneWidget);
              await tester.tap(find.text('Cancel'));
            }
          }
          await tester.pumpAndSettle();
          expect(hardware.discardedDrafts, [BigInt.one]);
          expect(h.operations.checkpoints, 0);
          expect(h.operations.broadcasts, 0);
        },
      );
    }
  }
}

Future<void> _reviewCard(WidgetTester tester, {required bool mobile}) async {
  await tester.tap(
    mobile
        ? find.byKey(const ValueKey('payment_links_mobile_create_button'))
        : find.text('Create new card'),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('payment_link_amount_editor')),
    '1',
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(
    find.byKey(
      ValueKey(
        mobile
            ? 'payment_link_mobile_amount_continue_button'
            : 'payment_link_amount_continue_button',
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!mobile) {
    await tester.tap(find.text('Start typing…'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(
    find.byKey(const ValueKey('payment_link_message_editor')),
    'Keep this message',
  );
  await tester.pump();
  await tester.tap(
    mobile
        ? find.byKey(
            const ValueKey('payment_link_mobile_message_continue_button'),
          )
        : find.text('Review & confirm'),
  );
  await tester.pumpAndSettle();
}

class _FeeTransitionHardware extends FakePaymentLinkHardwareSigningService {
  final firstPreparation = Completer<void>();
  bool nu7 = false;
  final quotes = <PaymentLinkFundingQuote?>[];
  final presentations = <PaymentLinkPresentation?>[];

  @override
  Future<PaymentLinkHardwarePcztDraft> createFundingPczt({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
    PaymentLinkFundingQuote? expectedQuote,
  }) async {
    quotes.add(expectedQuote);
    presentations.add(presentation);
    if (quotes.length == 1) await firstPreparation.future;
    if (expectedQuote!.claimFeeReserveZatoshi !=
        BigInt.from(nu7 ? 2000 : 10000)) {
      throw const PaymentLinkBatchQuoteChanged();
    }
    return super.createFundingPczt(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
      presentation: presentation,
      expectedQuote: expectedQuote,
    );
  }

  @override
  PaymentLinkHardwarePcztDraft get draft => PaymentLinkHardwarePcztDraft(
    link: incomingLink,
    pcztBytes: const [1, 2, 3],
    needsSaplingParams: false,
    feeZatoshi: BigInt.from(nu7 ? 2000 : 10000),
    proposalId: BigInt.one,
    sendFlowId: 'test-payment-link-hardware',
  );
}

class _FeeTransitionOperations extends FakePaymentLinkOperations {
  _FeeTransitionOperations(this.hardware);
  final _FeeTransitionHardware hardware;
  bool failQuote = false;

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) async {
    await super.quoteFunding(
      amountZatoshi: amountZatoshi,
      sourceAccountUuid: sourceAccountUuid,
    );
    if (failQuote) throw StateError('quote unavailable');
    final fee = BigInt.from(hardware.nu7 ? 2000 : 10000);
    return PaymentLinkFundingQuote(
      sourceAccountUuid: sourceAccountUuid,
      recipientAmountZatoshi: amountZatoshi,
      fundingFeeZatoshi: fee,
      claimFeeReserveZatoshi: fee,
    );
  }
}
