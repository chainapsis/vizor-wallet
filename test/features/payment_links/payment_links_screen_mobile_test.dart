@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_cards_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_qr_share_card.dart';

import '../../support/payment_links_screen_support.dart';

void main() {
  testWidgets('copying an older card preserves creation order after reload', (
    tester,
  ) async {
    final older = PaymentLinkRecoveryRecord(
      link: otherAccountLink,
      sourceAccountUuid: 'account-1',
      claimFeeReserveZatoshi: BigInt.from(10000),
      state: PaymentLinkRecoveryState.funded,
      updatedAt: DateTime.utc(2026, 8, 5),
      fundingTxids: 'funding-txid-2',
    );
    final operations = FakePaymentLinkOperations(
      records: [older, fundedRecovery],
    );
    final clipboard = FakePaymentLinkClipboard();
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    final newestRow = find.byKey(
      ValueKey('payment_link_mobile_recovery_${incomingLink.address}'),
    );
    final olderRow = find.byKey(
      ValueKey('payment_link_mobile_recovery_${otherAccountLink.address}'),
    );
    final originalPositions = [
      tester.getTopLeft(newestRow),
      tester.getTopLeft(olderRow),
    ];
    expect(originalPositions.first.dy, lessThan(originalPositions.last.dy));

    await tester.tap(
      find.descendant(
        of: olderRow,
        matching: find.byKey(
          const ValueKey('payment_link_mobile_card_copy_action'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(clipboard.copiedSecrets, [otherAccountLink.toUri().toString()]);
    expect(
      operations.records.first.updatedAt.isAfter(fundedRecovery.updatedAt),
      isTrue,
    );
    expect([
      tester.getTopLeft(newestRow),
      tester.getTopLeft(olderRow),
    ], originalPositions);
    final reloaded = await loadPaymentLinkCardsSnapshot(operations);
    expect(reloaded.created.map((record) => record.link.address), [
      incomingLink.address,
      otherAccountLink.address,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile share and copy keep independent pending feedback', (
    tester,
  ) async {
    final copyGate = Completer<void>();
    final shareGate = Completer<bool>();
    final clipboard = FakePaymentLinkClipboard(copyCompleter: copyGate);
    final operations = FakePaymentLinkOperations(records: [fundedRecovery]);
    final images = <Uint8List>[];
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
      qrShareHandler: ({required png, required sharePositionOrigin}) async {
        images.add(png);
        return shareGate.future;
      },
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Show gift card QR code'));
    await tester.pumpAndSettle();
    final copy = find.byKey(const ValueKey('payment_link_share_copy_button'));
    await tester.tap(copy);
    await tester.pump();
    expect(find.text('Copying...'), findsOneWidget);
    expect(find.text('Sharing...'), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Share card'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Share card'));
    await tester.pump();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 50 && images.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    expect(images, hasLength(1));
    expect(find.text('Sharing...'), findsOneWidget);
    copyGate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Sharing...'), findsOneWidget);
    expect(tester.widget<AppButton>(copy).onPressed, isNotNull);
    await tester.tap(find.text('Sharing...'), warnIfMissed: false);
    await tester.pump();
    expect(images, hasLength(1));
    shareGate.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Share card'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);
    expect(operations.sharedLinks, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('copying one card leaves other list icons unchanged', (
    tester,
  ) async {
    final gate = Completer<void>();
    final clipboard = FakePaymentLinkClipboard(copyCompleter: gate);
    final second = PaymentLinkRecoveryRecord(
      link: otherAccountLink,
      sourceAccountUuid: 'account-1',
      claimFeeReserveZatoshi: BigInt.from(10000),
      state: PaymentLinkRecoveryState.funded,
      updatedAt: DateTime.utc(2026, 8, 5),
      fundingTxids: 'funding-txid-2',
    );
    final operations = FakePaymentLinkOperations(
      records: [fundedRecovery, second],
    );
    await pumpPaymentLinksScreen(
      tester,
      operations: operations,
      clipboard: clipboard,
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    final copy = find.byKey(
      const ValueKey('payment_link_mobile_card_copy_action'),
    );
    final qr = find.byKey(const ValueKey('payment_link_mobile_card_qr_action'));
    Color? iconColor(Finder action) => tester
        .widget<AppIcon>(
          find.descendant(of: action, matching: find.byType(AppIcon)).first,
        )
        .color;
    final qrColor = iconColor(qr.first);
    final otherCopyColor = iconColor(copy.last);
    await tester.tap(copy.first);
    await tester.pump();
    expect(clipboard.copiedSecrets, hasLength(1));
    expect(iconColor(qr.first), qrColor);
    expect(iconColor(qr.last), qrColor);
    expect(iconColor(copy.last), otherCopyColor);
    await tester.pump(const Duration(milliseconds: 60));
    expect(iconColor(qr.first), qrColor);
    expect(iconColor(copy.last), otherCopyColor);
    await tester.tap(copy.first, warnIfMissed: false);
    await tester.pump();
    expect(clipboard.copiedSecrets, hasLength(1));
    await tester.tap(copy.last);
    await tester.pump();
    expect(clipboard.copiedSecrets, hasLength(2));
    await tester.tap(qr.first);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentLinkQrShareCard), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(operations.sharedLinks, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final settings in [
    (true, true, 100.0),
    (true, false, 100.0),
    (false, false, 100.0),
    (true, false, null),
  ]) {
    testWidgets(
      'completed card keeps saved fiat through waiting and sharing $settings',
      (tester) async {
        final source = _PendingCardPrice();
        source.result.complete(
          settings.$3 == null ? null : ZecMarketData(usdPrice: settings.$3!),
        );
        final operations = FakePaymentLinkOperations(
          fundingBroadcastAcceptedOnCreate: false,
          fundingConfirmationCount: 0,
        );
        final clipboard = FakePaymentLinkClipboard();
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          clipboard: clipboard,
          marketDataSource: source,
          pricingEnabled: settings.$1,
        );
        await tester.binding.setSurfaceSize(const Size(390, 844));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('payment_links_mobile_create_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('payment_link_amount_editor')),
          '1.25',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('payment_link_mobile_amount_continue_button'),
          ),
        );
        await tester.pumpAndSettle();
        if (settings.$2) {
          await tester.enterText(
            find.byKey(const ValueKey('payment_link_message_editor')),
            'For you',
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(
            const ValueKey('payment_link_mobile_message_continue_button'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey('payment_link_mobile_review_continue_button'),
          ),
        );
        await tester.pumpAndSettle();

        final hasFiat = settings.$1 && settings.$3 != null;
        void expectSavedFiat() {
          expect(
            find.text(r'$125.00'),
            hasFiat ? findsOneWidget : findsNothing,
          );
          expect(find.text('Fiat unavailable'), findsNothing);
          expect(
            find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
            findsNothing,
          );
        }

        expectSavedFiat();
        expect(find.text('Copy link'), findsNothing);
        operations.fundingConfirmationCount = 1;
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
        expectSavedFiat();
        expect(find.text('Copy link'), findsOneWidget);
        if (settings.$2) {
          await tester.tap(find.bySemanticsLabel('Flip gift card'));
          await tester.pumpAndSettle();
          expect(find.text('For you'), findsOneWidget);
          await tester.tap(find.bySemanticsLabel('Flip gift card'));
          await tester.pumpAndSettle();
          expectSavedFiat();
        }
        await tester.pump(zecMarketDataRefreshInterval);
        await tester.pumpAndSettle();
        expectSavedFiat();
        expect(source.fetchCount, settings.$1 ? 1 : 0);
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(
          VizorPaymentLink.parse(
            clipboard.copiedSecrets.single,
          ).presentation?.fiatSnapshot?.amount,
          hasFiat ? 125 : null,
        );
        await tester.tap(
          find.byKey(const ValueKey('payment_link_mobile_ready_home_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Show gift card QR code'));
        await tester.pumpAndSettle();
        final qr = tester.widget<PaymentLinkQrShareCard>(
          find.byType(PaymentLinkQrShareCard),
        );
        expect(
          VizorPaymentLink.parse(qr.qrData).presentation?.fiatSnapshot?.amount,
          hasFiat ? 125 : null,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final outcome in [
    (PaymentLinkAvailability.claimedElsewhere, 'Already claimed'),
    (PaymentLinkAvailability.noBalance, 'No balance'),
    (PaymentLinkAvailability.failed, 'Claim failed'),
  ]) {
    testWidgets('shows ${outcome.$2} inside the mobile redeem area', (
      tester,
    ) async {
      final operations = FakePaymentLinkOperations(claimable: false)
        ..claimAvailability = outcome.$1;
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        clipboard: FakePaymentLinkClipboard(
          text: incomingLink.toUri().toString(),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_links_mobile_redeem_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_paste_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Redeem the Card'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('payment_link_mobile_redeem_drop_zone'),
          ),
          matching: find.text(outcome.$2),
        ),
        findsOneWidget,
      );
      expect(find.text('Check status'), findsOneWidget);
      expect(operations.claimedLinks, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final settings in [
    (true, true, true),
    (true, true, false),
    (false, true, true),
    (true, false, true),
  ]) {
    testWidgets('Redeem card shows only the saved fiat snapshot $settings', (
      tester,
    ) async {
      await pumpPaymentLinksScreen(
        tester,
        bootstrap: homeBootstrap,
        pricingEnabled: settings.$1,
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final link = VizorPaymentLink(
        network: incomingLink.network,
        address: incomingLink.address,
        amountZatoshi: incomingLink.amountZatoshi,
        mnemonic: incomingLink.mnemonic,
        birthdayHeight: incomingLink.birthdayHeight,
        label: incomingLink.label,
        createdAt: incomingLink.createdAt,
        presentation: PaymentLinkPresentation(
          artworkId: 'ruby',
          message: settings.$3 ? 'Congratulations!' : null,
          fiatSnapshot: settings.$2
              ? const PaymentLinkFiatSnapshot(amount: 142.23)
              : null,
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(link.toUri().toString());
      await tester.pumpAndSettle();
      expect(find.byType(PaymentLinkGiftCard), findsWidgets);
      expect(
        find.text(r'$142.23'),
        settings.$1 && settings.$2 ? findsOneWidget : findsNothing,
      );
      // The current test market price would value this card at $445.
      expect(find.text(r'$445.00'), findsNothing);
      expect(find.text('Fiat unavailable'), findsNothing);
    });
  }

  setUpAll(loadPaymentLinksTestFonts);

  testWidgets(
    'mobile keeps a saved unavailable Card during destination preparation',
    (tester) async {
      final accounts = SwitchablePaymentLinkAccountNotifier();
      final operations = FakePaymentLinkOperations(
        receivedRecords: [PaymentLinkReceivedRecord.fromLink(incomingLink)],
        readClaimDestination: () => accounts.current,
      );
      await _openReceivedCard(tester, operations, accountNotifier: accounts);
      await tester.tap(find.text('Claim the gift'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_account-2')),
      );
      operations.claimable = false;
      await tester.tap(find.text('Claim gift'));
      await tester.pumpAndSettle();
      expect(operations.claimedLinks, isEmpty);
      expect(operations.discardedClaimAddresses, isEmpty);
      expect(operations.retainedClaimAddresses, [incomingLink.address]);
      expect(
        operations.receivedRecords.single.claimLink?.toUri(),
        incomingLink.toUri(),
      );
      expect(
        find.text('There is currently no balance available to claim.'),
        findsOneWidget,
      );
    },
  );
  for (final pricingEnabled in [true, false]) {
    testWidgets(
      'creation snapshots fiat only with pricing enabled: $pricingEnabled',
      (tester) async {
        final operations = FakePaymentLinkOperations();
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          pricingEnabled: pricingEnabled,
        );
        await tester.tap(
          find.byKey(const ValueKey('payment_links_mobile_create_button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('payment_link_amount_editor')),
          '1.25',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        for (final key in [
          'payment_link_mobile_amount_continue_button',
          'payment_link_mobile_message_continue_button',
          'payment_link_mobile_review_continue_button',
        ]) {
          if (key == 'payment_link_mobile_review_continue_button') {
            expect(
              find.text(r'$125.00'),
              pricingEnabled ? findsOneWidget : findsNothing,
            );
          }
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
        }
        expect(operations.createdFiatSnapshots, hasLength(1));
        expect(
          operations.createdFiatSnapshots.single?.amount,
          pricingEnabled ? 125 : null,
        );
      },
    );
  }

  testWidgets(
    'disabled pricing hides all fiat status while amount entry and Max work',
    (tester) async {
      final source = _PendingCardPrice();
      await pumpPaymentLinksScreen(
        tester,
        pricingEnabled: false,
        marketDataSource: source,
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_links_mobile_create_button')),
      );
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('payment_link_amount_editor'));
      final max = find.byKey(const ValueKey('payment_link_max_button'));
      expect(find.textContaining('Use max:'), findsOneWidget);

      for (final amount in ['0', '2']) {
        await tester.enterText(editor, amount);
        await tester.pumpAndSettle();
        expect(find.text('Fiat unavailable'), findsNothing);
        expect(find.textContaining(r'$'), findsNothing);
        expect(
          find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
          findsNothing,
        );
        expect(max, findsOneWidget);
      }
      await tester.tap(max);
      await tester.pumpAndSettle();
      expect(
        parseZecAmount(tester.widget<EditableText>(editor).controller.text),
        greaterThan(BigInt.from(200000000)),
      );
      expect(find.text('Fiat unavailable'), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(source.fetchCount, 0);
      expect(
        tester
            .widget<AppButton>(
              find.byKey(
                const ValueKey('payment_link_mobile_amount_continue_button'),
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'actual amount screen replaces Use max with fiat loading and the latest value',
    (tester) async {
      final source = _PendingCardPrice();
      await pumpPaymentLinksScreen(tester, marketDataSource: source);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_links_mobile_create_button')),
      );
      await tester.pumpAndSettle();
      final max = find.byKey(const ValueKey('payment_link_max_button'));
      final editor = find.byKey(const ValueKey('payment_link_amount_editor'));
      final loading = find.byKey(
        const ValueKey('payment_link_fiat_loading_placeholder'),
      );
      expect(find.textContaining('Use max:'), findsOneWidget);
      expect(max, findsNothing);
      expect(loading, findsNothing);

      await tester.enterText(editor, '4.45');
      await tester.pump();
      expect(find.textContaining('Use max:'), findsNothing);
      expect(loading, findsOneWidget);
      expect(max, findsOneWidget);
      await tester.enterText(editor, '2');
      await tester.pump();
      source.result.complete(const ZecMarketData(usdPrice: 100));
      await tester.pumpAndSettle();
      expect(find.text(r'$200.00'), findsOneWidget);
      expect(find.text(r'$445.00'), findsNothing);
      expect(loading, findsNothing);
      expect(max, findsOneWidget);

      for (final amount in ['0', '2', '', '2']) {
        await tester.enterText(editor, amount);
        await tester.pump();
        expect(loading, findsNothing);
        if (amount == '2') expect(find.text(r'$200.00'), findsOneWidget);
        expect(source.fetchCount, 1);
      }

      await tester.enterText(editor, '');
      await tester.pumpAndSettle();
      expect(find.textContaining('Use max:'), findsOneWidget);
      expect(find.text(r'$200.00'), findsNothing);
      expect(max, findsNothing);

      await tester.tap(find.textContaining('Use max:'));
      await tester.pumpAndSettle();
      final entered = tester.widget<EditableText>(editor).controller.text;
      final fiat = fiatTextForZatoshi(
        parseZecAmount(entered)!,
        zecUsdUnitPrice: 100,
      );
      expect(find.text(fiat!), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey('payment_link_mobile_amount_continue_button'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('payment_link_mobile_message_continue_button'),
        ),
      );
      await tester.pump();
      expect(find.text('Review a Card'), findsOneWidget);
      expect(find.text(fiat), findsOneWidget);
      expect(loading, findsNothing);
      expect(source.fetchCount, 1);
    },
  );

  testWidgets(
    'fiat fetch failure ends loading without blocking card creation',
    (tester) async {
      final source = _PendingCardPrice();
      await pumpPaymentLinksScreen(tester, marketDataSource: source);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_links_mobile_create_button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('payment_link_amount_editor')),
        '2',
      );
      await tester.pump();
      source.result.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Fiat unavailable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_link_fiat_loading_placeholder')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('payment_link_max_button')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(
                const ValueKey('payment_link_mobile_amount_continue_button'),
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'canceling the Redeem scanner keeps the paste screen and no Received record',
    (tester) async {
      final scan = Completer<VizorPaymentLink?>();
      final operations = FakePaymentLinkOperations();
      var scanCalls = 0;
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        scanner: (context, {required networkName}) {
          expect(networkName, 'main');
          scanCalls++;
          return scan.future;
        },
      );
      await _openRedeemScanner(tester);
      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_scan_button')),
      );
      expect(scanCalls, 1);
      scan.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Paste card link'), findsOneWidget);
      expect(operations.preparedLinks, isEmpty);
      expect(operations.receivedRecords, isEmpty);
    },
  );

  testWidgets(
    'a QR preview does not claim or save, and closing discards its scan',
    (tester) async {
      final operations = FakePaymentLinkOperations();
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        scanner: (context, {required networkName}) async => incomingLink,
      );
      await _openRedeemScanner(tester);
      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(operations.claimedSessions, isEmpty);
      expect(operations.receivedRecords, isEmpty);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(operations.discardedClaimAddresses, [incomingLink.address]);
      expect(operations.receivedRecords, isEmpty);
    },
  );

  testWidgets(
    'QR claim selects an account only after preview and opens its home',
    (tester) async {
      final accounts = SwitchablePaymentLinkAccountNotifier();
      final operations = FakePaymentLinkOperations(
        readClaimDestination: () => accounts.current,
      );
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        accountNotifier: accounts,
        scanner: (context, {required networkName}) async => incomingLink,
      );
      await _openRedeemScanner(tester);
      expect(
        find.byKey(const ValueKey('payment_link_claim_account_sheet')),
        findsNothing,
      );
      final router = GoRouter.of(
        tester.element(
          find.byKey(const ValueKey('payment_links_mobile_screen')),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_claim_button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_account-2')),
      );
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_confirm')),
      );
      await tester.pumpAndSettle();
      expect(
        operations.claimedSessions.single.destinationAccountUuid,
        'account-2',
      );
      expect(accounts.current.activeAccountUuid, 'account-2');
      expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    },
  );

  testWidgets(
    'a failed QR balance check retries the decoded card without scanning again',
    (tester) async {
      final operations = FakePaymentLinkOperations(prepareClaimFailures: 1);
      var scanCalls = 0;
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        scanner: (context, {required networkName}) async {
          scanCalls++;
          return incomingLink;
        },
      );
      await _openRedeemScanner(tester);
      expect(find.text('Try again'), findsOneWidget);
      expect(operations.receivedRecords, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_paste_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(scanCalls, 1);
      expect(operations.preparedLinks.map((link) => link.address), [
        incomingLink.address,
        incomingLink.address,
      ]);
      expect(operations.receivedRecords, isEmpty);
    },
  );

  for (final waiting in [false, true]) {
    testWidgets(
      'closing a scanned ${waiting ? 'waiting' : 'claimable'} card leaves no Received entry',
      (tester) async {
        final operations = FakePaymentLinkOperations(
          waitingForFundingConfirmations: waiting,
          fundingConfirmationCount: waiting ? 0 : 4,
        );
        final router = await _openReceivedCard(tester, operations);
        expect(operations.claimedSessions, isEmpty);
        await tester.tap(
          waiting
              ? find.byKey(
                  const ValueKey('payment_link_mobile_ready_home_button'),
                )
              : find.bySemanticsLabel('Close'),
        );
        await tester.pumpAndSettle();
        expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
        expect(operations.receivedRecords, isEmpty);
        expect(operations.retainedClaimAddresses, isEmpty);
        expect(operations.discardedClaimAddresses, [incomingLink.address]);

        router.go('/payment-links');
        await tester.pumpAndSettle();
        expect(find.text('No Gift Cards yet'), findsOneWidget);
      },
    );
  }

  for (final longScan in [false, true]) {
    testWidgets(
      '${longScan ? 'declining a long scan' : 'a failed scan'} does not add a mobile Received entry',
      (tester) async {
        final operations = FakePaymentLinkOperations(
          longSyncConfirmationRequired: longScan,
          prepareClaimFailures: longScan ? 0 : 1,
        );
        final router = await _openReceivedCard(tester, operations);
        if (longScan) {
          await tester.tap(find.text('Go back'));
          await tester.pumpAndSettle();
        } else {
          expect(find.text('Try again'), findsOneWidget);
        }
        router.go('/home');
        await tester.pumpAndSettle();
        expect(operations.receivedRecords, isEmpty);
        expect(operations.keptLinkAddresses, isEmpty);
        router.go('/payment-links');
        await tester.pumpAndSettle();
        expect(find.text('No Gift Cards yet'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'claim defaults to the active account and cancellation keeps it',
    (tester) async {
      final accounts = SwitchablePaymentLinkAccountNotifier(
        twoAccountState.copyWith(activeAccountUuid: 'account-2'),
      );
      final operations = FakePaymentLinkOperations(
        readClaimDestination: () => accounts.current,
      );
      final router = await _openReceivedCard(
        tester,
        operations,
        accountNotifier: accounts,
      );
      await tester.tap(find.text('Claim the gift'));
      await tester.pumpAndSettle();
      expect(operations.claimedSessions, isEmpty);
      expect(operations.receivedRecords, isEmpty);

      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_account-1')),
      );
      await tester.pump();
      expect(accounts.current.activeAccountUuid, 'account-2');
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(accounts.switchedAccounts, isEmpty);

      await _claimGift(tester, chooseAccount: true);
      await tester.pumpAndSettle();
      expect(
        operations.claimedSessions.single.destinationAccountUuid,
        'account-2',
      );
      expect(accounts.switchedAccounts, isEmpty);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
      expect(accounts.current.activeAccountUuid, 'account-2');
    },
  );

  testWidgets(
    'claim switches, prepares for that account, then opens its home',
    (tester) async {
      final accounts = SwitchablePaymentLinkAccountNotifier();
      final prepare = Completer<void>();
      final claim = Completer<PaymentLinkClaimResult>();
      final operations = FakePaymentLinkOperations(
        readClaimDestination: () => accounts.current,
        prepareClaimGates: {2: prepare},
        claimCompleter: claim,
      );
      final router = await _openReceivedCard(
        tester,
        operations,
        accountNotifier: accounts,
      );
      await tester.tap(find.text('Claim the gift'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_account-2')),
      );
      await tester.tap(find.text('Claim gift'));
      await tester.pumpAndSettle();

      expect(accounts.current.activeAccountUuid, 'account-2');
      expect(find.text('Preparing...'), findsOneWidget);
      expect(operations.claimedSessions, isEmpty);
      expect(operations.discardedClaimAddresses, isEmpty);
      // Preparation owns the destination; another tap or system Back cannot
      // change it or start a second claim while the first action is awaiting.
      await tester.tap(
        find.byKey(const ValueKey('payment_link_claim_account_account-1')),
      );
      await tester.tap(find.text('Preparing...'));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Preparing...'), findsOneWidget);
      expect(accounts.switchedAccounts, ['account-2']);

      prepare.complete();
      await tester.pumpAndSettle();
      expect(find.text('Claiming...'), findsOneWidget);
      final submitted = operations.claimedSessions.single;
      expect(submitted.destinationAccountUuid, 'account-2');
      expect(submitted.destinationAddress, 'u1account-2address');
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/payment-links',
      );
      claim.complete(broadcastedClaimResult);
      await _pumpClaimFrames(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
      expect(accounts.current.activeAccountUuid, 'account-2');
    },
  );

  testWidgets('preparation failure keeps the selected account for retry', (
    tester,
  ) async {
    final accounts = SwitchablePaymentLinkAccountNotifier();
    final operations = FakePaymentLinkOperations(
      readClaimDestination: () => accounts.current,
    );
    await _openReceivedCard(tester, operations, accountNotifier: accounts);
    operations.prepareClaimFailures = 1;
    await tester.tap(find.text('Claim the gift'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_claim_account_account-2')),
    );
    await tester.tap(find.text('Claim gift'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Couldn’t prepare this gift. Try again or choose another account.',
      ),
      findsOneWidget,
    );
    expect(accounts.current.activeAccountUuid, 'account-2');
    expect(operations.claimedSessions, isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('payment_link_claim_account_confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      operations.claimedSessions.single.destinationAccountUuid,
      'account-2',
    );
    expect(accounts.switchedAccounts, ['account-2']);
  });

  testWidgets('leaving during an account switch does not submit a claim', (
    tester,
  ) async {
    final gate = Completer<void>();
    final accounts = SwitchablePaymentLinkAccountNotifier()..switchGate = gate;
    final operations = FakePaymentLinkOperations(
      readClaimDestination: () => accounts.current,
    );
    final router = await _openReceivedCard(
      tester,
      operations,
      accountNotifier: accounts,
    );
    await tester.tap(find.text('Claim the gift'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('payment_link_claim_account_account-2')),
    );
    await tester.tap(find.text('Claim gift'));
    await tester.pump();
    router.go('/settings');
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(operations.claimedSessions, isEmpty);
    expect(operations.discardedClaimAddresses, [incomingLink.address]);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/settings');
  });

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
    expect(operations.keptLinkAddresses, isEmpty);

    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check gift card'));
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

      await _claimGift(tester);
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
    final messageFocus = tester
        .widget<TextField>(
          find.byKey(const ValueKey('payment_link_message_editor')),
        )
        .focusNode!;
    expect(messageFocus.hasFocus, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(messageFocus.hasFocus, isFalse);

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

  testWidgets(
    'one account claims directly and keeps the card until broadcast',
    (tester) async {
      final claim = Completer<PaymentLinkClaimResult>();
      final operations = FakePaymentLinkOperations(claimCompleter: claim);
      final router = await _openReceivedCard(tester, operations);

      await _claimGift(tester);
      expect(operations.claimedSessions, hasLength(1));
      expect(
        operations.claimedSessions.single.destinationAccountUuid,
        'account-1',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/payment-links',
      );
      expect(find.text('Claiming...'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('payment_link_mobile_claim_button')),
      );
      await tester.pump();
      expect(operations.claimedLinks, hasLength(1));
      expect(operations.discardedClaimAddresses, isEmpty);

      claim.complete(broadcastedClaimResult);
      await _pumpClaimFrames(tester);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
      expect(
        find.byKey(const ValueKey('payment_links_mobile_screen')),
        findsNothing,
      );
    },
  );

  for (final failure in [
    (
      name: 'network failure',
      error: StateError('grpc connect failed'),
      message:
          "Couldn't finish receiving this gift. Try again to check its status.",
    ),
    (
      name: 'receiving account change',
      error: const PaymentLinkClaimDestinationChangedException(),
      message: 'Receiving account changed. Try again to check this gift.',
    ),
  ]) {
    testWidgets(
      'mobile ${failure.name} keeps the card and rechecks before retrying',
      (tester) async {
        final claim = Completer<PaymentLinkClaimResult>();
        final claims = {incomingLink.address: claim};
        final operations = FakePaymentLinkOperations(claimCompleters: claims);
        final router = await _openReceivedCard(tester, operations);

        await _claimGift(tester);
        await tester.pump();
        claim.completeError(failure.error);
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/payment-links',
        );
        expect(find.text(failure.message), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(
          operations.receivedRecords.single.status,
          PaymentLinkReceivedStatus.readyToClaim,
        );

        claims.clear();
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(operations.allowLongSyncCalls, hasLength(2));
        expect(operations.claimedLinks, hasLength(1));
        expect(find.text('Claim the gift'), findsOneWidget);

        await _claimGift(tester);
        expect(operations.claimedLinks, hasLength(2));
        expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
      },
    );
  }

  for (final status in [
    PaymentLinkClaimBroadcastStatus.pendingBroadcast,
    PaymentLinkClaimBroadcastStatus.partialBroadcast,
  ]) {
    testWidgets(
      'mobile shows $status in Received instead of leaving for Home',
      (tester) async {
        final claim = Completer<PaymentLinkClaimResult>();
        final operations = FakePaymentLinkOperations(claimCompleter: claim);
        final router = await _openReceivedCard(tester, operations);

        await _claimGift(tester);
        await tester.pump();
        claim.complete(
          PaymentLinkClaimResult(txids: 'pending-claim', status: status),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/payment-links',
        );
        expect(find.text('Checking result'), findsOneWidget);
        expect(
          find.text('Claim result is not confirmed. Check its status.'),
          findsOneWidget,
        );
        expect(find.text('Claim the gift'), findsNothing);
        expect(find.text('Try again'), findsNothing);
      },
    );
  }

  testWidgets(
    'leaving a mobile claim keeps its wallet and does not navigate on completion',
    (tester) async {
      final claim = Completer<PaymentLinkClaimResult>();
      final operations = FakePaymentLinkOperations(claimCompleter: claim);
      final router = await _openReceivedCard(tester, operations);

      await _claimGift(tester);
      await tester.pump();
      router.go('/settings');
      await tester.pumpAndSettle();
      claim.complete(broadcastedClaimResult);
      await _pumpClaimFrames(tester);

      expect(operations.discardedClaimAddresses, isEmpty);
      expect(router.routerDelegate.currentConfiguration.uri.path, '/settings');
    },
  );

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

  for (final outcome in ['shared', 'cancelled', 'failed']) {
    testWidgets('mobile Gift Card QR export is $outcome', (tester) async {
      final operations = FakePaymentLinkOperations(records: [fundedRecovery]);
      final result = Completer<bool>();
      final images = <Uint8List>[];
      Rect? origin;
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        qrShareHandler: ({required png, required sharePositionOrigin}) async {
          images.add(png);
          origin = sharePositionOrigin;
          return result.future;
        },
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Show gift card QR code'));
      await tester.pumpAndSettle();
      final card = tester.widget<PaymentLinkQrShareCard>(
        find.byType(PaymentLinkQrShareCard),
      );
      expect(card.artwork, PaymentLinkCardArtwork.ruby);
      expect(card.qrData, incomingLink.toUri().toString());
      expect(operations.sharedLinks, isEmpty);

      await tester.tap(find.text('Share card'));
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 50; attempt++) {
          if (images.isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(images, hasLength(1));
      expect(
        images.single.take(8),
        orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
      );
      final pngSize = ByteData.sublistView(images.single, 16, 24);
      expect(pngSize.getUint32(0), 1188);
      expect(pngSize.getUint32(4), 810);
      expect(origin!.isEmpty, isFalse);
      expect(operations.sharedLinks, isEmpty);
      await tester.tap(find.text('Sharing...'));
      await tester.pump();
      expect(images, hasLength(1));

      if (outcome == 'failed') {
        result.completeError(StateError('Native share unavailable'));
      } else {
        result.complete(outcome == 'shared');
      }
      await tester.pumpAndSettle();
      expect(
        operations.sharedLinks,
        outcome == 'shared' ? [incomingLink] : isEmpty,
      );
      expect(find.text('Share card'), findsOneWidget);
      if (outcome == 'failed') {
        expect(
          find.text("Couldn't share this gift card. Copy the link instead."),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('payment_link_share_copy_button')),
        );
        await tester.pumpAndSettle();
        expect(operations.sharedLinks, [incomingLink]);
      }
    });
  }

  testWidgets('mobile received tab lists an in-flight claim', (tester) async {
    final operations = FakePaymentLinkOperations(
      receivedRecords: [
        PaymentLinkReceivedRecord(
          claimSubmittedAt: DateTime.utc(2026, 8, 28),
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

class _PendingCardPrice implements ZecMarketDataSource {
  final result = Completer<ZecMarketData?>();
  int fetchCount = 0;

  @override
  Future<ZecMarketData?> fetchMarketData() {
    fetchCount++;
    return result.future;
  }
}

Future<void> _openRedeemScanner(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('payment_links_mobile_redeem_button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('payment_link_mobile_scan_button')),
  );
  await tester.pumpAndSettle();
}

Future<GoRouter> _openReceivedCard(
  WidgetTester tester,
  FakePaymentLinkOperations operations, {
  SwitchablePaymentLinkAccountNotifier? accountNotifier,
}) async {
  await pumpPaymentLinksScreen(
    tester,
    operations: operations,
    bootstrap: homeBootstrap,
    accountNotifier: accountNotifier,
  );
  await tester.binding.setSurfaceSize(const Size(390, 844));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  container
      .read(paymentLinkIntakeProvider.notifier)
      .receive(incomingLink.toUri().toString());
  await tester.pumpAndSettle();
  return GoRouter.of(
    tester.element(find.byKey(const ValueKey('payment_links_mobile_screen'))),
  );
}

Future<void> _claimGift(
  WidgetTester tester, {
  bool chooseAccount = false,
}) async {
  await tester.tap(
    find.byKey(const ValueKey('payment_link_mobile_claim_button')),
  );
  await _pumpClaimFrames(tester);
  expect(
    find.byKey(const ValueKey('payment_link_claim_account_sheet')),
    chooseAccount ? findsOneWidget : findsNothing,
  );
  if (chooseAccount) {
    await tester.tap(
      find.byKey(const ValueKey('payment_link_claim_account_confirm')),
    );
    await tester.pump();
  }
}

// Claim/Home keep an in-progress animation until confirmation; settling all
// animations is not a completion condition for a successful broadcast.
Future<void> _pumpClaimFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}
