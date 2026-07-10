@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_status_content.dart';

const _recipient = '0x12351aBcDeF01234567890123456789076123';

Widget _harness(Widget child, {AppThemeData theme = AppThemeData.light}) {
  return MaterialApp(
    builder: (_, navigator) => AppTheme(data: theme, child: navigator!),
    home: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          disableAnimations: true,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 393,
            height: 852,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

MobileSwapReviewHeaderRow _unusedRow() => MobileSwapReviewHeaderRow(
  label: "You're receiving",
  amountText: '4.125 ZEC',
  asset: SwapAsset.zec,
);

SwapActivityStatusPresentation _presentation({required bool completed}) {
  return SwapActivityStatusPresentation(
    title: completed ? 'Payment complete' : 'Payment in progress',
    payAsset: SwapAsset.zec,
    receiveAsset: SwapAsset.usdc,
    payFiatText: r'$250.12',
    receiveFiatText: r'$250.12',
    payAmountText: '4.125 ZEC',
    receiveAmountText: '990 USDC',
    badgeKind: completed
        ? SwapStatusBadgeKind.completed
        : SwapStatusBadgeKind.liveQuote,
    progressIndex: completed ? 3 : 1,
    steps: const [],
    details: [
      const SwapStatusDetailRowData(
        label: 'Timestamp',
        value: 'May 20, 2026 13:20',
      ),
      SwapStatusDetailRowData(
        label: 'Tx ID',
        value: '0123123124512512',
        linkUri: Uri.parse('https://explorer.near-intents.org/transactions/1'),
      ),
      const SwapStatusDetailRowData(
        label: 'Converted from',
        value: '4.125 ZEC',
      ),
      const SwapStatusDetailRowData(
        label: 'Tx fee',
        value: '0.0125 ZEC',
        help: true,
      ),
    ],
    progressTabLabel: 'Payment progress',
    paymentMode: true,
    showTabs: !completed,
  );
}

Widget _content({required bool completed}) {
  return MobileSwapStatusContent(
    presentation: _presentation(completed: completed),
    paymentHeader: const MobilePayStatusHeader(
      asset: SwapAsset.usdc,
      amountText: '990 USDC',
      fiatText: r'$250.12',
      recipientAddress: _recipient,
      recipientName: 'Mike',
      recipientProfilePictureId: 'pfp-08',
    ),
    payHeaderRow: _unusedRow(),
    receiveHeaderRow: _unusedRow(),
    activeTab: SwapStatusTab.details,
    detailsExpanded: false,
    onTabChanged: (_) {},
    onToggleDetails: () {},
  );
}

void main() {
  testWidgets('paying uses payment asset and recipient status layout', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_content(completed: false)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text("You're paying"), findsOneWidget);
    expect(find.text('990 USDC'), findsOneWidget);
    expect(find.text(r'$250.12'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('0x12351...76123'), findsOneWidget);
    expect(find.text('Full address'), findsOneWidget);
    expect(find.text('Payment progress'), findsOneWidget);
    expect(find.text('Transaction details'), findsOneWidget);
    expect(find.text('In progress...'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('Tx ID'), findsOneWidget);
    expect(find.text('Converted from'), findsOneWidget);
    expect(find.text('Tx fee'), findsOneWidget);
    expect(find.text("You're receiving"), findsNothing);

    expect(
      tester.getSize(find.byKey(const ValueKey('mobile_pay_status_header'))),
      const Size(361, 252),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile_swap_status_card')))
          .width,
      361,
    );
  });

  testWidgets('paid keeps the Figma card offset and dark theme tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_content(completed: true), theme: AppThemeData.dark),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Payment progress'), findsNothing);
    expect(find.text('Transaction details'), findsNothing);

    final header = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_status_header')),
    );
    final card = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_status_card')),
    );
    expect(card.top - header.bottom, 76);
  });

  test('mobile pay status mapper provides the Figma transaction rows', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(status: SwapIntentStatus.processing),
    );

    expect(presentation.paymentMode, isTrue);
    expect(
      presentation.details.map((row) => row.label),
      containsAll(['Timestamp', 'Tx ID', 'Converted from', 'Tx fee']),
    );
  });

  test('mobile activity titles distinguish paying and paid from swap', () {
    expect(
      mobileSwapActivityTitle(
        _state(),
        _intent(status: SwapIntentStatus.processing),
      ),
      'Paying ...',
    );
    expect(
      mobileSwapActivityTitle(
        _state(),
        _intent(status: SwapIntentStatus.complete),
      ),
      'Paid',
    );

    final swap = _intent(status: SwapIntentStatus.processing, payMode: false);
    expect(mobileSwapActivityTitle(_state(), swap), 'Swap in progress...');
  });
}

SwapState _state() {
  return const SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [],
  );
}

SwapIntent _intent({required SwapIntentStatus status, bool payMode = true}) {
  return SwapIntent(
    id: 'mobile-pay-status',
    pair: 'ZEC -> USDC',
    sellAmount: '4.125 ZEC',
    receiveEstimate: '990 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Payment in progress',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: '0123123124512512',
    depositTxHash: 'zec-shielded-spend-txid',
    nearIntentHash: 'near-intent-hash',
    oneClickRecipient: _recipient,
    totalFeesText: '0.0125 ZEC',
    createdAt: DateTime.utc(2026, 5, 20, 13, 20),
    completedAt: status == SwapIntentStatus.complete
        ? DateTime.utc(2026, 5, 20, 13, 21)
        : null,
    payMode: payMode,
  );
}
