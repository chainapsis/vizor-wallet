import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_scanner_provider.dart';

import '../../support/payment_links_screen_support.dart';

Finder keyed(String key) => find.byKey(ValueKey(key));

class _MemoryImportStorage implements GiftClaimImportStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> delete() async => value = null;
}

void main() {
  Future<void> openRedeem(
    WidgetTester tester, {
    required FakePaymentLinkOperations operations,
    required PaymentLinkScanner scanner,
  }) async {
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      scanner: scanner,
      giftImportStore: GiftClaimImportStore(storage: _MemoryImportStorage()),
    );
    await tester.tap(find.text('Redeem a card'));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop scanner cancellation releases both input actions', (
    tester,
  ) async {
    final pending = Completer<VizorPaymentLink?>();
    final operations = FakePaymentLinkOperations();
    var calls = 0;
    await openRedeem(
      tester,
      operations: operations,
      scanner: (context, {required networkName}) {
        expect(networkName, 'main');
        calls++;
        return pending.future;
      },
    );
    final scan = keyed('payment_link_desktop_scan_button');
    final paste = keyed('payment_link_redeem_paste_button');
    await tester.tap(scan);
    await tester.pump();
    expect(tester.widget<AppButton>(scan).onPressed, isNull);
    expect(tester.widget<AppButton>(paste).onPressed, isNull);
    await tester.tap(scan);
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(scan).onPressed, isNotNull);
    expect(tester.widget<AppButton>(paste).onPressed, isNotNull);
    await tester.tap(scan);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(operations.preparedLinks, isEmpty);
    expect(operations.receivedRecords, isEmpty);
  });

  testWidgets('desktop QR preview waits for consent and discards on Back', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations();
    await openRedeem(
      tester,
      operations: operations,
      scanner: (context, {required networkName}) async => incomingLink,
    );
    await tester.tap(keyed('payment_link_desktop_scan_button'));
    await tester.pumpAndSettle();
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    expect(operations.claimedSessions, isEmpty);
    expect(operations.receivedRecords, isEmpty);
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(operations.discardedClaimAddresses, [incomingLink.address]);
    expect(operations.receivedRecords, isEmpty);
  });

  testWidgets('desktop QR inspection retry reuses the decoded link', (
    tester,
  ) async {
    final operations = FakePaymentLinkOperations(prepareClaimFailures: 1);
    var calls = 0;
    await openRedeem(
      tester,
      operations: operations,
      scanner: (context, {required networkName}) async {
        calls++;
        return incomingLink;
      },
    );
    await tester.tap(keyed('payment_link_desktop_scan_button'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('You’ve received\na gift card!'), findsOneWidget);
    expect(calls, 1);
    expect(operations.preparedLinks.map((link) => link.address), [
      incomingLink.address,
      incomingLink.address,
    ]);
    expect(operations.claimedSessions, isEmpty);
    expect(operations.receivedRecords, isEmpty);
  });

  testWidgets('leaving desktop Redeem ignores a late scanner result', (
    tester,
  ) async {
    final pending = Completer<VizorPaymentLink?>();
    final operations = FakePaymentLinkOperations();
    await openRedeem(
      tester,
      operations: operations,
      scanner: (context, {required networkName}) => pending.future,
    );
    await tester.tap(keyed('payment_link_desktop_scan_button'));
    await tester.pump();
    await tester.tap(find.text('My Cards'));
    await tester.pumpAndSettle();
    pending.complete(incomingLink);
    await tester.pumpAndSettle();
    expect(find.text('You’ve received\na gift card!'), findsNothing);
    expect(operations.preparedLinks, isEmpty);
    expect(operations.receivedRecords, isEmpty);
  });
}
