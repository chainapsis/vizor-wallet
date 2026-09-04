@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';

import '../../support/payment_links_screen_support.dart';

void main() {
  setUpAll(loadPaymentLinksTestFonts);

  testWidgets('mobile confirms before checking a Gift Card with a long scan', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(
      longSyncConfirmationRequired: true,
    );
    final clipboard = FakePaymentLinkClipboard(
      text: incomingLink.toUri().toString(),
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );

    expect(
      find.byKey(const ValueKey('payment_links_mobile_screen')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('payment_links_mobile_redeem_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payment_link_long_sync_warning_sheet')),
      findsOneWidget,
    );
    expect(operations.allowLongSyncCalls, [isFalse]);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('payment_link_long_sync_warning_sheet')),
      findsNothing,
    );
    expect(operations.keptLinkAddresses, [incomingLink.address]);

    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check Gift Card'));
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncCalls, [isFalse, isFalse, isTrue]);
    expect(find.text('You’ve received a gift!'), findsOneWidget);
  });

  testWidgets(
    'mobile keeps a checked Gift Card out of Received until claim starts',
    (tester) async {
      final operations = FakePaymentLinkOperations();
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        bootstrap: homeBootstrap,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );

      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(incomingLink.toUri().toString());
      await tester.pumpAndSettle();

      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(operations.receivedRecords, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_claim_button')),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(operations.receivedRecords, hasLength(1));
      expect(
        operations.receivedRecords.single.status,
        PaymentLinkReceivedStatus.receiving,
      );
    },
  );

  testWidgets('mobile system back steps the wizard instead of leaving it', (
    tester,
  ) async {
    await pumpPaymentLinksScreen(tester);

    await tester.tap(
      find.byKey(const ValueKey('payment_links_mobile_create_button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_amount_editor')),
      '0.1',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_amount_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payment_link_mobile_message_continue_button')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('payment_links_mobile_screen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_mobile_amount_continue_button')),
      findsOneWidget,
    );
    expect(find.text('0.1'), findsOneWidget);
  });

  testWidgets('mobile home lists a funded card and copies its link', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(records: [sharedRecovery]);
    await pumpPaymentLinksScreen(tester, operations: operations);

    // Before this list existed the mobile home only offered Create/Redeem,
    // so a funded link was unreachable once the Ready page was left.
    expect(
      find.byKey(
        const ValueKey('payment_link_mobile_recovery_u1paymentlinkaddress'),
      ),
      findsOneWidget,
    );
    expect(find.text('4.45 ZEC'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_card_copy_action')),
    );
    await tester.pumpAndSettle();

    expect(operations.sharedLinks, [incomingLink]);
  });

  testWidgets('mobile received tab lists an in-flight claim', (tester) async {
    final operations = FakePaymentLinkOperations(
      receivedRecords: [
        PaymentLinkReceivedRecord(
          network: incomingLink.network,
          address: incomingLink.address,
          amountZatoshi: incomingLink.amountZatoshi,
          createdAt: incomingLink.createdAt,
          artworkId: incomingLink.presentation?.artworkId,
          message: incomingLink.presentation?.message,
          status: PaymentLinkReceivedStatus.receiving,
          claimLink: incomingLink,
          destinationAccountUuid: 'account-1',
          claimTxids: 'claim-txid',
          updatedAt: DateTime.utc(2026, 8, 6, 2),
        ),
      ],
    );
    await pumpPaymentLinksScreen(tester, operations: operations);

    await tester.tap(
      find.byKey(const ValueKey('payment_links_mobile_received_tab')),
    );
    // The receiving row spins a loader, so this never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(
        const ValueKey('payment_link_mobile_received_u1paymentlinkaddress'),
      ),
      findsOneWidget,
    );
    expect(find.text('Receiving...'), findsOneWidget);
  });
}
