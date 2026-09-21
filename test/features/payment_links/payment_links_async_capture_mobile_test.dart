@Tags(['mobile', 'figma-capture'])
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import '../../support/payment_links_screen_support.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  const output = String.fromEnvironment('GIFT_CARD_CAPTURE_DIR');
  if (output.isEmpty) return;
  setUpAll(loadFigmaCompareFonts);
  // Visual parity uses an uninterrupted flow; back behavior is a separate run.
  for (final exerciseBack in [false, true]) {
    for (final state in [
      'funding',
      'funding-error',
      'metadata',
      'checking',
      'claiming',
      'claim-error',
      'account-preparing',
    ]) {
      testWidgets(
        'capture ${exerciseBack ? 'back behavior' : 'same state'} gift card $state',
        (tester) async {
          final boundary = GlobalKey();
          final gate = Completer<void>();
          final claim = Completer<PaymentLinkClaimResult>();
          final accounts = SwitchablePaymentLinkAccountNotifier();
          final operations = state == 'claim-error'
              ? _ClaimSaveFailure(gate)
              : FakePaymentLinkOperations(
                  createFundedLinkGate: state.startsWith('funding')
                      ? gate
                      : null,
                  fundingMetadataSavedOnCreate: state != 'metadata',
                  prepareClaimGates: state == 'checking'
                      ? {1: gate}
                      : state == 'account-preparing'
                      ? {2: gate}
                      : {},
                  claimCompleter: state == 'claiming' ? claim : null,
                  readClaimDestination: state == 'account-preparing'
                      ? () => accounts.current
                      : null,
                );
          await pumpPaymentLinksScreen(
            tester,
            logicalSize: const Size(393, 852),
            captureBoundaryKey: boundary,
            operations: operations,
            accountNotifier: state == 'account-preparing' ? accounts : null,
            clipboard: FakePaymentLinkClipboard(
              text: incomingLink.toUri().toString(),
            ),
          );
          final router = GoRouter.of(
            tester.element(
              find.byKey(const ValueKey('payment_links_mobile_screen')),
            ),
          );
          router.go('/settings');
          await tester.pumpAndSettle();
          unawaited(router.push('/payment-links'));
          await tester.pumpAndSettle();
          Future<void> frames() async {
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }

          Future<void> tap(String key) async {
            await tester.tap(find.byKey(ValueKey(key)));
            await frames();
          }

          Future<void> capture(String suffix) async {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 150)),
            );
            await frames();
            final lane = exerciseBack ? 'back-behavior' : 'same-state';
            final file = File('$output/$lane/$state-$suffix.png');
            file.parent.createSync(recursive: true);
            await expectLater(
              find.byKey(boundary),
              matchesGoldenFile(file.uri),
            );
          }

          if (state.startsWith('funding') || state == 'metadata') {
            await tap('payment_links_mobile_create_button');
            await tester.enterText(
              find.byKey(const ValueKey('payment_link_amount_editor')),
              '0.1',
            );
            await frames();
            await tap('payment_link_mobile_amount_continue_button');
            await tap('payment_link_mobile_message_continue_button');
            await tap('payment_link_mobile_review_continue_button');
          } else {
            await tap('payment_links_mobile_redeem_button');
            await tester.tap(find.text('Paste card link'));
            await frames();
            if (state == 'claiming' ||
                state == 'claim-error' ||
                state == 'account-preparing') {
              await tap('payment_link_mobile_claim_button');
              if (state == 'account-preparing') {
                await tap('payment_link_claim_account_account-2');
                await tester.tap(find.text('Claim gift'));
                await frames();
              }
            }
          }
          if (state == 'checking') {
            expect(
              find.byKey(const ValueKey('payment_link_mobile_redeem_checking')),
              findsOneWidget,
            );
          } else {
            expect(
              find.text(switch (state) {
                'funding' || 'funding-error' => 'Creating...',
                'metadata' => 'Try saving again',
                'claiming' || 'claim-error' => 'Claiming...',
                'account-preparing' => 'Preparing...',
                _ => 'Checking card...',
              }),
              findsOneWidget,
            );
          }
          await capture('pending');
          if (exerciseBack) {
            await tester.binding.handlePopRoute();
            await frames();
            await capture('back');
          }
          if (!gate.isCompleted) {
            if (state == 'funding-error' || state == 'claim-error') {
              gate.completeError(StateError('connection lost'));
            } else {
              gate.complete();
            }
          }
          if (!claim.isCompleted) claim.complete(broadcastedClaimResult);
          await frames();
          if (!exerciseBack) {
            if (state == 'claiming' || state == 'account-preparing') {
              expect(router.state.uri.path, '/home');
            } else {
              expect(
                find.text(switch (state) {
                  'funding' => 'Go home',
                  'funding-error' => 'Approve & create',
                  'metadata' => 'Try saving again',
                  'claim-error' => 'Try again',
                  _ => 'Claim the gift',
                }),
                findsOneWidget,
              );
            }
          }
          await capture('settled');
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}

class _ClaimSaveFailure extends FakePaymentLinkOperations {
  _ClaimSaveFailure(this.gate);
  final Completer<void> gate;
  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    await gate.future;
    return super.claimPreparedLink(session);
  }
}
