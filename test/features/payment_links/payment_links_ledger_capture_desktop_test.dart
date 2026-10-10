@Tags(['figma-capture'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_card_selector_rail.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';

import '../../figma_compare/figma_compare_font_loader.dart';
import '../../fakes/fake_sync_notifier.dart';
import '../../support/ledger_gift_card_support.dart';
import '../../support/payment_links_screen_support.dart';

void main() {
  const output = String.fromEnvironment('LEDGER_UI_CAPTURE_DIR');
  if (output.isEmpty) return;
  setUpAll(loadFigmaCompareFonts);

  testWidgets('capture Ledger gift card limit UI', (tester) async {
    final harness = LedgerGiftHarness();
    final boundary = GlobalKey();
    await pumpPaymentLinksScreen(
      tester,
      bootstrap: ledgerGiftBootstrap,
      batchOperations: _CaptureBatchOperations(),
      ledgerFunding: harness.service,
      ledgerOperations: harness.operations,
      recoveryStore: harness.recovery,
      logicalSize: const Size(1280, 800),
      captureBoundaryKey: boundary,
      syncNotifier: FakeSyncNotifier(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          percentage: 1,
          displayTargetPercentage: 1,
          totalBalance: BigInt.from(14223000000),
          spendableBalance: BigInt.from(14223000000),
        ),
      ),
    );
    Future<void> capture(String name) =>
        _capture(tester, boundary, output, name);

    expect(find.text('Multiple cards'), findsOneWidget);
    expect(find.text('Up to 4 with Ledger'), findsOneWidget);
    expect(find.text('For a group'), findsNothing);
    await capture('01-ledger-entry');
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    await capture('01b-ledger-entry-compact');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('payment_link_create_batch_button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Create up to 4 cards at once with Ledger.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_bulk_count')),
      findsOneWidget,
    );
    for (var count = 2; count <= 4; count++) {
      expect(
        find.byKey(ValueKey('payment_link_bulk_preset_$count')),
        findsNothing,
      );
    }
    expect(
      find.byKey(const ValueKey('payment_link_bulk_preset_20')),
      findsNothing,
    );
    for (var count = 3; count <= 4; count++) {
      await tester.tap(
        find.byKey(const ValueKey('payment_link_bulk_increase')),
      );
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_bulk_amount')),
      '0.1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('payment_link_bulk_message')),
      'A gift for you',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Review 4 cards'), findsOneWidget);
    await capture('02-ledger-create-four');
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    await capture('02b-ledger-create-four-compact');
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review 4 cards'));
    await tester.pumpAndSettle();
    expect(find.text('Create 4 cards'), findsOneWidget);
    await capture('03-ledger-review-four');
  });

  testWidgets('capture Ledger entry in an existing card list', (tester) async {
    final harness = LedgerGiftHarness();
    final boundary = GlobalKey();
    await pumpPaymentLinksScreen(
      tester,
      bootstrap: ledgerGiftBootstrap,
      operations: FakePaymentLinkOperations(records: [fundedRecovery]),
      ledgerFunding: harness.service,
      ledgerOperations: harness.operations,
      recoveryStore: harness.recovery,
      logicalSize: const Size(1280, 800),
      captureBoundaryKey: boundary,
    );
    expect(find.text('Multiple cards'), findsOneWidget);
    expect(find.text('Up to 4 with Ledger'), findsOneWidget);
    expect(find.text('For a group'), findsNothing);
    void checkNoOverlap() => expect(
      tester
          .getRect(
            find.byKey(const ValueKey('payment_link_create_batch_button')),
          )
          .overlaps(tester.getRect(find.byType(PaymentLinkCardListRow))),
      isFalse,
    );
    checkNoOverlap();
    await _capture(tester, boundary, output, '05-ledger-cards-list-entry');
    await tester.binding.setSurfaceSize(const Size(1080, 720));
    await tester.pumpAndSettle();
    checkNoOverlap();
    await _capture(
      tester,
      boundary,
      output,
      '05b-ledger-cards-list-entry-compact',
    );
  });

  testWidgets('ordinary accounts keep the existing group UI', (tester) async {
    await pumpPaymentLinksScreen(tester);
    expect(find.text('For a group'), findsOneWidget);
    expect(find.text('Up to 4 with Ledger'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('payment_link_create_batch_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create cards for a group'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_bulk_count')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_link_bulk_preset_20')),
      findsOneWidget,
    );
  });
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String output,
  String name,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  final rail = find.byType(PaymentLinkCardSelectorRail);
  if (rail.evaluate().isNotEmpty) {
    tester
        .widget<PaymentLinkCardSelectorRail>(rail)
        .onSelected(PaymentLinkCardArtwork.ruby);
  }
  await tester.pumpAndSettle();
  final images = [
    for (final element in find.byType(Image).evaluate())
      (image: element.widget as Image, context: element),
  ];
  await tester.runAsync(() async {
    for (final entry in images) {
      await precacheImage(entry.image.image, entry.context);
    }
  });
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  final file = File('$output/$name.png');
  file.parent.createSync(recursive: true);
  await expectLater(find.byKey(boundary), matchesGoldenFile(file.uri));
  expect(tester.takeException(), isNull);
}

class _CaptureBatchOperations implements PaymentLinkBatchOperations {
  @override
  Future<PaymentLinkBatchDraft> prepareBatch({
    required int count,
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    required PaymentLinkPresentation presentation,
    List<String>? artworkIds,
  }) async => PaymentLinkBatchDraft(
    id: 'ledger-capture-batch',
    links: [
      for (var index = 0; index < count; index++)
        VizorPaymentLink(
          label: 'Gift card',
          network: 'main',
          address: 'u1capture$index',
          amountZatoshi: amountZatoshi,
          mnemonic: ledgerGiftLink.mnemonic,
          birthdayHeight: ledgerGiftLink.birthdayHeight,
          createdAt: ledgerGiftLink.createdAt,
          presentation: presentation,
        ),
    ],
    quote: PaymentLinkBatchQuote(
      sourceAccountUuid: sourceAccountUuid,
      count: count,
      recipientAmountZatoshi: amountZatoshi,
      fundingFeeZatoshi: BigInt.from(20000),
    ),
  );

  @override
  Future<PaymentLinkBatchFundingResult> fundBatch(
    PaymentLinkBatchDraft draft,
  ) => throw StateError('Capture does not fund real cards.');

  @override
  Future<void> abandonUnsubmittedBatch(String batchId) async {}

  @override
  Future<void> retryBatchFundingMetadata({
    required String batchId,
    required String fundingTxids,
  }) async {}
}
