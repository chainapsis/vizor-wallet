import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_check_progress_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'payment_links_screen_support.dart';

/// Run the same preparation transitions in both separately compiled UI lanes.
void registerGiftCardClaimCheckingChecks({required bool mobile}) {
  for (final (name, error, expected) in [
    ('network failure', StateError('offline'), 'Try again'),
    (
      'invalid card',
      const FormatException('invalid'),
      'The link doesn’t look legit.',
    ),
    (
      'long scan warning',
      const PaymentLinkLongSyncConfirmationRequired(),
      'This gift card may take a while',
    ),
  ]) {
    testWidgets('a discovered gift returns to $name instead of claim actions', (
      tester,
    ) async {
      final gate = Completer<void>();
      final operations = FakePaymentLinkOperations(
        prepareClaimGates: {1: gate},
        prepareClaimError: error,
      );
      final container = await _showDiscoveredGift(
        tester,
        operations,
        mobile: mobile,
      );
      gate.complete();
      container
          .read(giftCardCheckProgressProvider.notifier)
          .clear(incomingLink);
      await tester.pumpAndSettle();
      expect(find.text('Checking your\ngift card'), findsNothing);
      expect(
        find.text(mobile ? 'Claim the gift' : 'Claim the gift card'),
        findsNothing,
      );
      expect(find.text(expected), findsWidgets);
      expect(operations.claimedSessions, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final availability in [
    PaymentLinkAvailability.noBalance,
    PaymentLinkAvailability.claimedElsewhere,
  ]) {
    testWidgets('a discovered gift shows the existing $availability outcome', (
      tester,
    ) async {
      final gate = Completer<void>();
      final operations = FakePaymentLinkOperations(prepareClaimGates: {1: gate})
        ..claimable = false
        ..claimAvailability = availability;
      final container = await _showDiscoveredGift(
        tester,
        operations,
        mobile: mobile,
      );
      gate.complete();
      container
          .read(giftCardCheckProgressProvider.notifier)
          .clear(incomingLink);
      await tester.pumpAndSettle();
      expect(find.text('Checking your\ngift card'), findsNothing);
      expect(
        find.text(mobile ? 'Claim the gift' : 'Claim the gift card'),
        findsNothing,
      );
      expect(
        find.text(
          availability == PaymentLinkAvailability.noBalance
              ? 'No balance'
              : 'Claimed elsewhere',
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a discovered gift waits for funding confirmations before claim actions',
    (tester) async {
      final gate = Completer<void>();
      final operations = FakePaymentLinkOperations(
        prepareClaimGates: {1: gate},
        waitingForFundingConfirmations: true,
        fundingConfirmationCount: 1,
      );
      final container = await _showDiscoveredGift(
        tester,
        operations,
        mobile: mobile,
      );
      gate.complete();
      container
          .read(giftCardCheckProgressProvider.notifier)
          .clear(incomingLink);
      await tester.pumpAndSettle();
      expect(find.text('Checking your\ngift card'), findsNothing);
      expect(find.text('Your Gift Card\nis almost ready!'), findsOneWidget);
      expect(
        find.text(mobile ? 'Claim the gift' : 'Claim the gift card'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a discovered gift keeps waiting after the stream ends until preparation returns',
    (tester) async {
      final gate = Completer<void>();
      final operations = FakePaymentLinkOperations(
        prepareClaimGates: {1: gate},
      );
      final container = await _showDiscoveredGift(
        tester,
        operations,
        mobile: mobile,
      );
      container
          .read(giftCardCheckProgressProvider.notifier)
          .clear(incomingLink);
      await tester.pump();
      expect(find.text('Checking your\ngift card'), findsOneWidget);
      expect(
        find.text(mobile ? 'Claim the gift' : 'Claim the gift card'),
        findsNothing,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Checking your\ngift card'), findsNothing);
      expect(
        find.text(mobile ? 'Claim the gift' : 'Claim the gift card'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProviderContainer> _showDiscoveredGift(
  WidgetTester tester,
  FakePaymentLinkOperations operations, {
  required bool mobile,
}) async {
  await pumpPaymentLinksScreen(
    tester,
    operations: operations,
    clipboard: FakePaymentLinkClipboard(text: incomingLink.toUri().toString()),
    logicalSize: mobile ? const Size(393, 852) : const Size(1080, 720),
  );
  await tester.tap(find.text('Redeem a card'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Paste card link'));
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp).first),
  );
  container
      .read(giftCardCheckProgressProvider.notifier)
      .update(
        incomingLink,
        rust_sync.ApiGiftCardCheckProgress(
          phase: 'checking',
          completed: BigInt.from(50),
          total: BigInt.from(100),
          fundingHeight: incomingLink.birthdayHeight + 1,
          checkedHeight: incomingLink.birthdayHeight + 50,
          totalZatoshi: incomingLink.amountZatoshi + BigInt.from(10000),
          unspentZatoshi: incomingLink.amountZatoshi + BigInt.from(10000),
          complete: false,
        ),
      );
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('Checking your\ngift card'), findsOneWidget);
  expect(find.text('Checking the gift… 50%'), findsOneWidget);
  expect(
    find.text(mobile ? 'Claim the gift' : 'Claim the gift card'),
    findsNothing,
  );
  return container;
}
