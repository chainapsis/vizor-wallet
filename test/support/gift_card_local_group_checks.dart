import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_cards_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_batch_detail_desktop_view.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';

import 'payment_links_screen_support.dart';

void registerGiftCardLocalGroupChecks({required bool mobile}) {
  final size = mobile ? const Size(390, 844) : const Size(1080, 720);
  final screenKey = ValueKey(
    mobile ? 'payment_links_mobile_screen' : 'payment_links_desktop_screen',
  );
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  List<PaymentLinkCardsSection> sections(WidgetTester tester) => mobile
      ? tester
            .widget<PaymentLinkCardsMobileView>(
              find.byType(PaymentLinkCardsMobileView),
            )
            .sections
      : tester
            .widget<PaymentLinkCardsDesktopView>(
              find.byType(PaymentLinkCardsDesktopView),
            )
            .sections;

  for (final snapshot in [false, true]) {
    for (final fail in [false, true]) {
      testWidgets(
        'local groups before funding (snapshot=$snapshot fail=$fail)',
        (tester) async {
          final records = [
            for (final (link, usage) in [
              (
                incomingLink,
                const GiftCardUsage(status: GiftCardUsageStatus.unused),
              ),
              (
                secondIncomingLink,
                const GiftCardUsage(status: GiftCardUsageStatus.used),
              ),
              (
                otherAccountLink,
                const GiftCardUsage(status: GiftCardUsageStatus.spendDetected),
              ),
              (
                unknownOriginLink,
                const GiftCardUsage(
                  reason: GiftCardUsageReason.awaitingConfirmation,
                ),
              ),
            ])
              PaymentLinkRecoveryRecord(
                link: link,
                sourceAccountUuid: 'account-1',
                state: PaymentLinkRecoveryState.funded,
                updatedAt: link.createdAt,
                fundingTxids: 'funding',
                claimFeeReserveZatoshi: BigInt.from(10000),
                usage: usage,
              ),
          ];
          final operations = _LocalGroupOperations(records);
          await pumpPaymentLinksScreen(
            tester,
            operations: operations,
            logicalSize: size,
          );
          if (snapshot) {
            final router = GoRouter.of(tester.element(find.byKey(screenKey)));
            router.go('/home');
            await frames(tester);
            final saved = await loadPaymentLinkCardsSnapshot(operations);
            router.go('/payment-links', extra: saved);
          }
          await frames(tester);
          Map<String, int> counts() => {
            for (final section in sections(tester))
              section.label: section.cards.length,
          };
          expect(counts(), {'Pending': 1, 'Unused': 1, 'Used': 2});
          expect(find.text('Confirming'), findsOneWidget);
          final rows = sections(tester).expand((section) => section.cards);
          for (final row in rows) {
            if (mobile) {
              expect((row as PaymentLinkCardListMobileRow).onCopyLink, isNull);
              expect(row.onShowQr, isNull);
            } else {
              expect((row as PaymentLinkCardListRow).onCopyLink, isNull);
              expect(row.onShowQr, isNull);
            }
          }
          if (fail) {
            operations.funding.completeError(StateError('offline'));
            operations.recovery.completeError(StateError('offline'));
            await frames(tester);
            expect(counts(), {'Pending': 1, 'Unused': 1, 'Used': 2});
          } else {
            operations.records[0] = records[0].copyWith(
              state: records[0].state,
              updatedAt: records[0].updatedAt,
              usage: const GiftCardUsage(status: GiftCardUsageStatus.used),
            );
            operations.funding.complete();
            operations.recovery.complete();
            await frames(tester);
            expect(counts(), {'Pending': 1, 'Used': 3});
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  if (!mobile) {
    for (final (usages, label) in [
      ([GiftCardUsageStatus.used, GiftCardUsageStatus.unknown], '1 of 2 used'),
      (
        [GiftCardUsageStatus.unused, GiftCardUsageStatus.unknown],
        '1 of 2 unused',
      ),
      ([GiftCardUsageStatus.unused, GiftCardUsageStatus.unused], 'Unused'),
      ([GiftCardUsageStatus.used, GiftCardUsageStatus.used], 'All used'),
    ]) {
      testWidgets('local batch summary and gated members: $label', (
        tester,
      ) async {
        final operations = _LocalGroupOperations([
          for (var i = 0; i < batchTestLinks.length; i++)
            PaymentLinkRecoveryRecord(
              link: batchTestLinks[i],
              sourceAccountUuid: 'account-1',
              state: PaymentLinkRecoveryState.funded,
              updatedAt: fundedRecovery.updatedAt,
              fundingTxids: 'funding',
              claimFeeReserveZatoshi: BigInt.from(10000),
              batchId: 'local-group',
              batchIndex: i + 1,
              batchCount: 2,
              usage: GiftCardUsage(status: usages[i]),
            ),
        ]);
        await pumpPaymentLinksScreen(
          tester,
          operations: operations,
          logicalSize: size,
        );
        await frames(tester);
        final row = tester.widget<PaymentLinkBatchListRow>(
          find.byKey(const ValueKey('payment_link_batch_local-group')),
        );
        expect(row.statusText, label);
        expect(row.showLoader, isTrue);
        row.onOpen();
        await frames(tester);
        var detail = tester.widget<PaymentLinkBatchDetailDesktopView>(
          find.byType(PaymentLinkBatchDetailDesktopView),
        );
        expect(detail.ready, isFalse);
        expect(detail.onExport, isNull);
        expect(find.byType(PaymentLinkBatchMemberRow), findsNWidgets(2));
        for (final member in tester.widgetList<PaymentLinkBatchMemberRow>(
          find.byType(PaymentLinkBatchMemberRow),
        )) {
          expect(member.onCopyLink, isNull);
          expect(member.onShowQr, isNull);
        }
        operations.funding.complete();
        operations.recovery.complete();
        await frames(tester);
        detail = tester.widget<PaymentLinkBatchDetailDesktopView>(
          find.byType(PaymentLinkBatchDetailDesktopView),
        );
        expect(detail.ready, isTrue);
        expect(detail.onExport, isNotNull);
        for (final member in tester.widgetList<PaymentLinkBatchMemberRow>(
          find.byType(PaymentLinkBatchMemberRow),
        )) {
          expect(member.onCopyLink, isNotNull);
          expect(member.onShowQr, isNotNull);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _LocalGroupOperations extends FakePaymentLinkOperations {
  _LocalGroupOperations(List<PaymentLinkRecoveryRecord> records)
    : super(records: records) {
    createdRecoveryGate = recovery;
  }
  final funding = Completer<void>();
  final recovery = Completer<void>();

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async {
    await funding.future;
    return super.inspectCreatedLinkFundings(records);
  }
}
