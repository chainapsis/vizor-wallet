@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_copy.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  testWidgets('a detected use animates into the Used section', (tester) async {
    const movingKey = ValueKey('moving-card');
    Widget row(Key key, String status) => PaymentLinkCardListMobileRow(
      key: key,
      thumbnail: const SizedBox(),
      amountText: '0.25 ZEC',
      dateText: 'September 17',
      statusText: status,
    );
    List<PaymentLinkCardsSection> sections({required bool detected}) => [
      PaymentLinkCardsSection(
        label: kPaymentLinkPendingSectionLabel,
        cards: detected ? const [] : [row(movingKey, 'Checking use')],
      ),
      PaymentLinkCardsSection(
        label: kPaymentLinkUnusedSectionLabel,
        cards: [row(const ValueKey('unused-card'), 'Unused card')],
      ),
      PaymentLinkCardsSection(
        label: kPaymentLinkUsedSectionLabel,
        cards: [
          if (detected) row(movingKey, 'Use detected'),
          row(const ValueKey('used-card'), 'Used card'),
        ],
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(393, 773));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_cardsApp(sections: sections(detected: false)));
    await tester.pumpAndSettle();
    final oldTop = tester.getTopLeft(find.byKey(movingKey)).dy;

    await tester.pumpWidget(_cardsApp(sections: sections(detected: true)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 140));
    expect(find.byKey(movingKey), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.byKey(movingKey), findsOneWidget);
    final usedHeading = find.text(kPaymentLinkUsedSectionLabel);
    expect(
      tester.getTopLeft(find.byKey(movingKey)).dy,
      greaterThan(tester.getTopLeft(usedHeading).dy),
    );
    expect(tester.getTopLeft(find.byKey(movingKey)).dy, isNot(oldTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty tab keeps the create and redeem actions reachable', (
    tester,
  ) async {
    await _pumpCards(
      tester,
      sections: const [PaymentLinkCardsSection(label: 'Received', cards: [])],
      activeTab: PaymentLinkCardsTab.received,
      emptyLabel: kPaymentLinkNoReceivedCardsText,
    );

    expect(find.text(kPaymentLinkNoReceivedCardsText), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_links_mobile_cards_list')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('payment_links_mobile_create_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('payment_links_mobile_redeem_button')),
      findsOneWidget,
    );
  });

  testWidgets('the list fills the page behind floating actions', (
    tester,
  ) async {
    final rows = List.generate(
      10,
      (index) => PaymentLinkCardListMobileRow(
        key: ValueKey('received-card-$index'),
        thumbnail: const SizedBox(),
        amountText: '${index + 1}.00 ZEC',
        dateText: 'September ${index + 1}',
        statusText: 'Received',
      ),
    );
    await _pumpCards(
      tester,
      activeTab: PaymentLinkCardsTab.received,
      sections: [
        PaymentLinkCardsSection(label: 'Received', cards: rows),
      ],
    );

    final list = find.byKey(
      const ValueKey('payment_links_mobile_cards_list'),
    );
    final redeem = find.byKey(
      const ValueKey('payment_links_mobile_redeem_button'),
    );
    expect(tester.getRect(list).bottom, greaterThan(tester.getRect(redeem).top));

    await tester.drag(list, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('10.00 ZEC'), findsOneWidget);
    expect(
      tester.getRect(find.text('10.00 ZEC')).bottom,
      lessThan(tester.getRect(redeem).top),
    );
  });

  testWidgets('a funded unshared card exposes copy and QR actions', (
    tester,
  ) async {
    var copies = 0;
    var qrOpens = 0;
    await _pumpCards(
      tester,
      sections: [
        PaymentLinkCardsSection(
          label: kPaymentLinkPendingSectionLabel,
          cards: [
            PaymentLinkCardListMobileRow(
              thumbnail: const SizedBox(),
              amountText: '4.45 ZEC',
              dateText: 'August 7',
              showLinkActions: true,
              onCopyLink: () => copies += 1,
              onShowQr: () => qrOpens += 1,
            ),
          ],
        ),
      ],
    );

    expect(find.text('4.45 ZEC'), findsOneWidget);
    expect(find.text('August 7'), findsOneWidget);
    expect(find.text(kPaymentLinkPendingSectionLabel), findsOneWidget);
    // A funded card shows the copy action instead of a status label — this is
    // the affordance that was missing once the user left the Ready page.
    expect(find.bySemanticsLabel(kPaymentLinkCopyLinkSemanticLabel), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_card_copy_action')),
    );
    await tester.pump();

    expect(copies, 1);
    await tester.tap(find.bySemanticsLabel('Show gift card QR code'));
    await tester.pump();
    expect(qrOpens, 1);
  });

  testWidgets('an incomplete card shows its status instead of a copy action', (
    tester,
  ) async {
    await _pumpCards(
      tester,
      sections: const [
        PaymentLinkCardsSection(
          label: kPaymentLinkPendingSectionLabel,
          cards: [
            PaymentLinkCardListMobileRow(
              thumbnail: SizedBox(),
              amountText: '0.25 ZEC',
              dateText: 'July 2',
              statusText: kPaymentLinkFundingIncompleteStatus,
            ),
          ],
        ),
      ],
    );

    expect(find.text(kPaymentLinkFundingIncompleteStatus), findsOneWidget);
    expect(
      find.byKey(const ValueKey('payment_link_mobile_card_copy_action')),
      findsNothing,
    );
  });

  testWidgets('a receiving card shows its status and forwards no tap', (
    tester,
  ) async {
    await _pumpCards(
      tester,
      activeTab: PaymentLinkCardsTab.received,
      sections: const [
        PaymentLinkCardsSection(
          label: kPaymentLinkReceivedTabLabel,
          cards: [
            PaymentLinkCardListMobileRow(
              thumbnail: SizedBox(),
              amountText: '0.75 ZEC',
              dateText: 'August 4',
              statusText: 'Receiving...',
              showLoader: true,
            ),
          ],
        ),
      ],
    );

    expect(find.text('Receiving...'), findsOneWidget);
    expect(find.text('0.75 ZEC'), findsOneWidget);
    // A claim already in flight is not re-openable from the row.
    expect(find.bySemanticsLabel('Receiving...'), findsNothing);
  });

  testWidgets('tapping a tab reports the selection', (tester) async {
    final selections = <PaymentLinkCardsTab>[];
    await _pumpCards(
      tester,
      sections: const [PaymentLinkCardsSection(label: 'Received', cards: [])],
      onTabSelected: selections.add,
    );

    await tester.tap(
      find.byKey(const ValueKey('payment_links_mobile_received_tab')),
    );
    await tester.pump();

    expect(selections, [PaymentLinkCardsTab.received]);
  });
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<PaymentLinkCardsSection> sections,
  PaymentLinkCardsTab activeTab = PaymentLinkCardsTab.created,
  ValueChanged<PaymentLinkCardsTab>? onTabSelected,
  String? emptyLabel,
}) async {
  await tester.binding.setSurfaceSize(const Size(393, 773));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    _cardsApp(
      sections: sections,
      activeTab: activeTab,
      onTabSelected: onTabSelected,
      emptyLabel: emptyLabel,
    ),
  );
}

Widget _cardsApp({
  required List<PaymentLinkCardsSection> sections,
  PaymentLinkCardsTab activeTab = PaymentLinkCardsTab.created,
  ValueChanged<PaymentLinkCardsTab>? onTabSelected,
  String? emptyLabel,
}) => MaterialApp(
  builder: (_, navigator) =>
      AppTheme(data: AppThemeData.dark, child: navigator!),
  home: Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 393,
      height: 773,
      child: PaymentLinkCardsMobileView(
        sections: sections,
        activeTab: activeTab,
        onTabSelected: onTabSelected,
        emptyLabel: emptyLabel,
        onBack: _noop,
        onCreate: _noop,
        onRedeem: _noop,
      ),
    ),
  ),
);

void _noop() {}
