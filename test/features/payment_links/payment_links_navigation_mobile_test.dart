@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import '../../support/payment_links_screen_support.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_scan_sheet.dart';

const _amount = 'payment_link_mobile_amount_continue_button';
const _message = 'payment_link_mobile_message_continue_button';
const _review = 'payment_link_mobile_review_continue_button';
Finder keyed(String key) => find.byKey(ValueKey(key));

Future<GoRouter> openFromSettings(
  WidgetTester tester, {
  FakePaymentLinkOperations? operations,
  SwitchablePaymentLinkAccountNotifier? accounts,
  PaymentLinkScanner? scanner,
  FakePaymentLinkClipboard? clipboard,
}) async {
  await pumpPaymentLinksScreen(
    tester,
    operations: operations,
    accountNotifier: accounts,
    scanner: scanner,
    logicalSize: const Size(393, 852),
    clipboard:
        clipboard ??
        FakePaymentLinkClipboard(text: incomingLink.toUri().toString()),
  );
  final router = GoRouter.of(
    tester.element(keyed('payment_links_mobile_screen')),
  );
  router.go('/settings');
  await tester.pumpAndSettle();
  unawaited(router.push('/payment-links'));
  await tester.pumpAndSettle();
  return router;
}

Future<void> tap(WidgetTester tester, String key) async {
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
}

Future<void> createToReview(WidgetTester tester) async {
  await tap(tester, 'payment_links_mobile_create_button');
  await tester.enterText(keyed('payment_link_amount_editor'), '0.1');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
  await tap(tester, _amount);
  await tester.enterText(
    keyed('payment_link_message_editor'),
    'Keep this message',
  );
  await tester.pump();
  await tap(tester, _message);
}

Future<void> back(WidgetTester tester) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await tester.dragFrom(const Offset(1, 150), const Offset(360, 0));
  } else {
    await tester.binding.handlePopRoute();
  }
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadPaymentLinksTestFonts);
  final platforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });
  testWidgets('back traverses real gift card pages and preserves draft', (
    tester,
  ) async {
    final router = await openFromSettings(tester);
    await createToReview(tester);
    await back(tester);
    expect(keyed(_message), findsOneWidget);
    expect(find.text('Keep this message'), findsOneWidget);
    await back(tester);
    expect(keyed(_amount), findsOneWidget);
    expect(find.text('0.1'), findsOneWidget);
    await tap(tester, _amount);
    expect(find.text('Keep this message'), findsOneWidget);
    await back(tester);
    await back(tester);
    expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
    expect(router.state.uri.path, '/payment-links');
    await back(tester);
    expect(router.state.uri.path, '/settings');
  }, variant: platforms);

  testWidgets(
    'cancelled iOS swipe retains the page and message',
    (tester) async {
      await openFromSettings(tester);
      await createToReview(tester);
      final gesture = await tester.startGesture(const Offset(1, 150));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(keyed(_review), findsOneWidget);
      await back(tester);
      expect(find.text('Keep this message'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'funding blocks back until completion then discards draft routes',
    (tester) async {
      final gate = Completer<void>();
      await openFromSettings(
        tester,
        operations: FakePaymentLinkOperations(createFundedLinkGate: gate),
      );
      await createToReview(tester);
      await tester.tap(keyed(_review));
      await tester.pump();
      await back(tester);
      expect(keyed(_review), findsOneWidget);
      expect(find.text('Creating...'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Go home'), findsOneWidget);
      await back(tester);
      expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
      expect(keyed(_review), findsNothing);
    },
    variant: platforms,
  );

  testWidgets('funding back guard survives an active account change', (
    tester,
  ) async {
    final gate = Completer<void>();
    final accounts = SwitchablePaymentLinkAccountNotifier();
    await openFromSettings(
      tester,
      accounts: accounts,
      operations: FakePaymentLinkOperations(createFundedLinkGate: gate),
    );
    await createToReview(tester);
    await tester.tap(keyed(_review));
    await tester.pump();
    await accounts.switchAccount('account-2');
    await tester.pump();
    await back(tester);
    expect(keyed(_review), findsOneWidget);
    expect(find.text('Creating...'), findsOneWidget);
    expect(keyed('payment_links_mobile_create_button'), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Go home'), findsOneWidget);
  }, variant: platforms);

  testWidgets('unsaved funding metadata blocks every back path', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      fundingMetadataSavedOnCreate: false,
    );
    await openFromSettings(tester, operations: operations);
    await createToReview(tester);
    await tap(tester, _review);
    await back(tester);
    expect(find.text('Try saving again'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back').last);
    await tester.pumpAndSettle();
    expect(find.text('Try saving again'), findsOneWidget);
    expect(operations.createdAmounts, hasLength(1));
  }, variant: platforms);

  testWidgets('abandoned link check cannot reopen received preview', (
    tester,
  ) async {
    final gate = Completer<void>();
    final operations = FakePaymentLinkOperations(prepareClaimGates: {1: gate});
    await openFromSettings(tester, operations: operations);
    await tap(tester, 'payment_links_mobile_redeem_button');
    await tester.tap(find.text('Paste card link'));
    await tester.pump();
    await back(tester);
    expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
    expect(operations.discardedClaimAddresses, [incomingLink.address]);
    await tester.tap(keyed('payment_links_mobile_redeem_button'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Paste card link'), findsOneWidget);
    expect(keyed('payment_link_mobile_redeem_checking'), findsNothing);
  }, variant: platforms);

  testWidgets(
    'received preview back releases session and returns to cards',
    (tester) async {
      final operations = FakePaymentLinkOperations();
      final router = await openFromSettings(tester, operations: operations);
      await tap(tester, 'payment_links_mobile_redeem_button');
      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
      expect(router.state.uri.path, '/payment-links');
      expect(operations.discardedClaimAddresses, [incomingLink.address]);
    },
    variant: platforms,
  );

  testWidgets(
    'waiting received card Go home retains its explicit destination',
    (tester) async {
      final router = await openFromSettings(
        tester,
        operations: FakePaymentLinkOperations(
          waitingForFundingConfirmations: true,
        ),
      );
      await tap(tester, 'payment_links_mobile_redeem_button');
      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/home');
    },
    variant: platforms,
  );

  testWidgets(
    'received swipe reveals the cards destination',
    (tester) async {
      await openFromSettings(tester);
      await tap(tester, 'payment_links_mobile_redeem_button');
      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(1, 150));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('claim execution blocks every back path until completion', (
    tester,
  ) async {
    final gate = Completer<PaymentLinkClaimResult>();
    final operations = FakePaymentLinkOperations(claimCompleter: gate);
    final router = await openFromSettings(tester, operations: operations);
    await tap(tester, 'payment_links_mobile_redeem_button');
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('payment_link_mobile_claim_button'));
    await tester.pump();
    await back(tester);
    expect(find.text('Claiming...'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close').last);
    await tester.pump();
    expect(find.text('Claiming...'), findsOneWidget);
    expect(router.state.uri.path, '/payment-links');
    gate.complete(broadcastedClaimResult);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(router.state.uri.path, '/home');
    expect(operations.discardedClaimAddresses, isEmpty);
  }, variant: platforms);
  testWidgets('claim failure unlocks the existing preview for checking', (
    tester,
  ) async {
    final gate = Completer<PaymentLinkClaimResult>();
    final operations = FakePaymentLinkOperations(claimCompleter: gate);
    await openFromSettings(tester, operations: operations);
    await tap(tester, 'payment_links_mobile_redeem_button');
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('payment_link_mobile_claim_button'));
    await tester.pump();
    await back(tester);
    expect(find.text('Claiming...'), findsOneWidget);
    gate.completeError(StateError('submission failed'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    await back(tester);
    expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
  }, variant: platforms);

  testWidgets('failed funding after account change unlocks and requotes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final accounts = SwitchablePaymentLinkAccountNotifier();
    await openFromSettings(
      tester,
      accounts: accounts,
      operations: FakePaymentLinkOperations(createFundedLinkGate: gate),
    );
    await createToReview(tester);
    await tester.tap(keyed(_review));
    await tester.pump();
    await accounts.switchAccount('account-2');
    await tester.pump();
    expect(find.text('Creating...'), findsOneWidget);
    gate.completeError(StateError('funding failed'));
    await tester.pumpAndSettle();
    expect(keyed(_amount), findsOneWidget);
    await back(tester);
    expect(keyed('payment_links_mobile_create_button'), findsOneWidget);
  }, variant: platforms);

  testWidgets('scanner result from an earlier redeem visit is ignored', (
    tester,
  ) async {
    final gate = Completer<VizorPaymentLink?>();
    final operations = FakePaymentLinkOperations();
    await openFromSettings(
      tester,
      operations: operations,
      scanner: (context, {required networkName}) => gate.future,
    );
    await tap(tester, 'payment_links_mobile_redeem_button');
    await tester.tap(find.text('Scan QR code'));
    await tester.pump();
    await back(tester);
    await tap(tester, 'payment_links_mobile_redeem_button');
    gate.complete(incomingLink);
    await tester.pumpAndSettle();
    expect(find.text('Paste card link'), findsOneWidget);
    expect(operations.preparedLinks, isEmpty);
  }, variant: platforms);

  testWidgets('late clipboard clear cannot reset a new preview', (
    tester,
  ) async {
    final clipboard = _DelayedClearClipboard();
    await openFromSettings(tester, clipboard: clipboard);
    await tap(tester, 'payment_links_mobile_redeem_button');
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('payment_link_mobile_clear_clipboard_button'));
    await tester.pump();
    await back(tester);
    await tap(tester, 'payment_links_mobile_redeem_button');
    clipboard.text = incomingLink.toUri().toString();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    expect(keyed('payment_link_mobile_claim_button'), findsOneWidget);
    clipboard.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Claim the gift'), findsOneWidget);
  }, variant: platforms);
  testWidgets(
    'late clear preserves loading for a new check on the same visit',
    (tester) async {
      final clipboard = _DelayedClearClipboard();
      final gate = Completer<void>();
      await openFromSettings(
        tester,
        clipboard: clipboard,
        operations: FakePaymentLinkOperations(prepareClaimGates: {1: gate}),
      );
      await tap(tester, 'payment_links_mobile_redeem_button');
      await tester.tap(find.text('Paste card link'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('payment_link_mobile_clear_clipboard_button'));
      await tester.pump();
      clipboard.text = incomingLink.toUri().toString();
      await tester.tap(find.text('Paste card link'));
      await tester.pump();
      clipboard.gate.complete();
      await tester.pump();
      expect(keyed('payment_link_mobile_redeem_checking'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Claim the gift'), findsOneWidget);
    },
    variant: platforms,
  );
}

class _DelayedClearClipboard extends FakePaymentLinkClipboard {
  _DelayedClearClipboard() : super(text: 'invalid');
  final gate = Completer<void>();
  @override
  Future<void> clear() => gate.future;
}
