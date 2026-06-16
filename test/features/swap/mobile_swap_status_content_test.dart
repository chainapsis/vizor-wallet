@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/swap/domain/swap_asset.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_detail_tooltips.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart'
    show SwapDirection, SwapIntent, SwapIntentStatus;
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_status_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart'
    show mobileSwapStatusRecipientFullAddress;

Widget _harness(Widget child) {
  return MaterialApp(
    builder: (_, navigator) =>
        AppTheme(data: AppThemeData.light, child: navigator!),
    home: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(393, 852),
          disableAnimations: true,
        ),
        child: child,
      ),
    ),
  );
}

MobileSwapReviewHeaderRow _payRow() => MobileSwapReviewHeaderRow(
  label: "You're paying",
  amountText: '1.12 ZEC',
  asset: SwapAsset.zec,
  bottomText: r'$250.12',
);

MobileSwapReviewHeaderRow _receiveRow() => MobileSwapReviewHeaderRow(
  label: "You're receiving",
  amountText: '100.12 USDC',
  asset: SwapAsset.usdc,
  bottomText: 'To: 0x1125 ... 17512',
);

SwapActivityStatusPresentation _presentation({
  required bool showTabs,
  SwapStatusBadgeKind badgeKind = SwapStatusBadgeKind.liveQuote,
  List<SwapStatusDetailRowData> details = const [],
  List<SwapStatusStepData> steps = const [],
}) {
  return SwapActivityStatusPresentation(
    title: 'Swap in progress...',
    payAsset: SwapAsset.zec,
    receiveAsset: SwapAsset.usdc,
    payFiatText: r'$250.12',
    receiveFiatText: r'$250.12',
    payAmountText: '1.12 ZEC',
    receiveAmountText: '100.12 USDC',
    badgeKind: badgeKind,
    progressIndex: 0,
    steps: steps,
    details: details,
    showTabs: showTabs,
  );
}

Widget _content({
  required bool showTabs,
  SwapStatusTab activeTab = SwapStatusTab.details,
  SwapStatusBadgeKind badgeKind = SwapStatusBadgeKind.liveQuote,
  List<SwapStatusDetailRowData> details = const [],
  List<SwapStatusStepData> steps = const [],
}) {
  return MobileSwapStatusContent(
    presentation: _presentation(
      showTabs: showTabs,
      badgeKind: badgeKind,
      details: details,
      steps: steps,
    ),
    payHeaderRow: _payRow(),
    receiveHeaderRow: _receiveRow(),
    activeTab: activeTab,
    detailsExpanded: true,
    onTabChanged: (_) {},
    onToggleDetails: () {},
  );
}

SwapIntent _intent({
  required SwapDirection direction,
  required String recipient,
}) {
  return SwapIntent(
    id: 'status-intent',
    pair: direction == SwapDirection.externalToZec
        ? 'USDC -> ZEC'
        : 'ZEC -> USDC',
    sellAmount: direction == SwapDirection.externalToZec
        ? '100.00 USDC'
        : '1.00 ZEC',
    receiveEstimate: direction == SwapDirection.externalToZec
        ? '1.00 ZEC'
        : '100.00 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.processing,
    nextAction: 'Swap in progress',
    direction: direction,
    externalAsset: SwapAsset.usdc,
    depositAddress: 'deposit-address',
    oneClickRecipient: recipient,
    oneClickRefundTo: direction == SwapDirection.externalToZec
        ? '0xrefund-address'
        : 'u1refund-address',
  );
}

void main() {
  const details = [
    SwapStatusDetailRowData(
      label: 'Total fees',
      value: 'Included',
      help: true,
      helpTooltip: swapTotalFeesTooltip,
    ),
    SwapStatusDetailRowData(label: 'Timestamp', value: 'May 20, 2026 13:20'),
  ];

  test(
    'mobile status skips full-address verification for own Zcash receive',
    () {
      expect(
        mobileSwapStatusRecipientFullAddress(
          _intent(
            direction: SwapDirection.externalToZec,
            recipient: 'u1wallet-recipient-address',
          ),
        ),
        isNull,
      );

      expect(
        mobileSwapStatusRecipientFullAddress(
          _intent(
            direction: SwapDirection.zecToExternal,
            recipient: '0xexternal-recipient-address',
          ),
        ),
        '0xexternal-recipient-address',
      );
    },
  );

  testWidgets('terminal status card omits the View on Near Intents link', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: _content(
            showTabs: false,
            badgeKind: SwapStatusBadgeKind.completed,
            details: details,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('View on Near Intents'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_swap_status_explorer_link')),
      findsNothing,
    );
    // The terminal card itself still renders.
    expect(find.text('Completed'), findsOneWidget);
    expect(_tooltipWithMessage(swapTotalFeesTooltip), findsOneWidget);
  });

  testWidgets('in-progress (details tab) omits the View on Near Intents link', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: _content(
            showTabs: true,
            activeTab: SwapStatusTab.details,
            details: details,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('View on Near Intents'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_swap_status_explorer_link')),
      findsNothing,
    );
    expect(find.text('More details'), findsNothing);
    expect(find.text('Less details'), findsNothing);
    // The progress / details tab switcher is present in the live state.
    expect(
      find.byKey(const ValueKey('mobile_swap_status_tab_details')),
      findsOneWidget,
    );
    final progressRect = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_status_tab_progress')),
    );
    final detailsRect = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_status_tab_details')),
    );
    final contentRect = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_status_content')),
    );
    final tabGroupCenter = (progressRect.left + detailsRect.right) / 2;
    expect(tabGroupCenter, moreOrLessEquals(contentRect.center.dx));
  });

  testWidgets('progress active description wraps with Figma mobile typography', (
    tester,
  ) async {
    const description =
        'Confirm waiting for the source chain and provider to recognise the deposit';
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: _content(
            showTabs: true,
            activeTab: SwapStatusTab.progress,
            steps: const [
              SwapStatusStepData(
                title: 'Deposit confirmation',
                state: SwapStatusStepState.active,
                activeTitle: 'Deposit confirmation...',
                lastCheckedLabel: 'Last check: 1m ago',
                description: description,
              ),
              SwapStatusStepData(
                title: 'Swap',
                state: SwapStatusStepState.pending,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final descriptionText = tester.widget<Text>(find.text(description));
    expect(descriptionText.overflow, isNull);
    expect(descriptionText.style?.fontSize, AppTypography.bodyMedium.fontSize);
    expect(descriptionText.style?.height, AppTypography.bodyMedium.height);

    final loader = tester.widget<AppIcon>(
      find.byKey(const ValueKey('swap_status_active_step_loader')),
    );
    expect(loader.size, 20);
  });

  testWidgets('details tab compacts copyable addresses only once', (
    tester,
  ) async {
    const fullAddress = '0x9aDFd236b6ccD57bd571ca3C538dbB55FE4819E2';
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: _content(
            showTabs: true,
            activeTab: SwapStatusTab.details,
            details: const [
              SwapStatusDetailRowData(
                label: 'Deposit USDC to',
                value: '0x9aDFd23 ... E4819E2',
                copyable: true,
                copyText: fullAddress,
              ),
              SwapStatusDetailRowData(label: 'Swap fee', value: 'Included'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Deposit USDC to'), findsOneWidget);
    expect(find.text('0x9aDF…819E2'), findsOneWidget);
    expect(find.text('0x9aDFd23 ... E4819E2'), findsNothing);
  });

  testWidgets('details tab keeps only the compact mobile transaction rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: _content(
            showTabs: true,
            activeTab: SwapStatusTab.details,
            details: [
              const SwapStatusDetailRowData(
                label: 'Account',
                value: 'Main account',
              ),
              const SwapStatusDetailRowData(
                label: 'Price protection',
                value: '0.04 ZEC (5.0%)',
              ),
              const SwapStatusDetailRowData(
                label: 'USDC recipient',
                value: '0x9aDF…Ef064',
              ),
              const SwapStatusDetailRowData(
                label: 'USDC refund address',
                value: '0xrefund…ddress',
              ),
              const SwapStatusDetailRowData(
                label: 'Deposit USDC to',
                value: '0xdeposit…ddress',
                copyable: true,
                copyText: '0xdeposit-address',
              ),
              const SwapStatusDetailRowData(label: 'Memo', value: '123456'),
              const SwapStatusDetailRowData(
                label: 'Missing deposit',
                value: '40 USDC',
              ),
              const SwapStatusDetailRowData(
                label: 'Required deposit',
                value: '100 USDC',
              ),
              const SwapStatusDetailRowData(
                label: 'Detected deposit',
                value: '60 USDC',
              ),
              const SwapStatusDetailRowData(
                label: 'Deposit deadline',
                value: 'May 20',
              ),
              const SwapStatusDetailRowData(
                label: 'Refund fee',
                value: '0.25 USDC',
              ),
              const SwapStatusDetailRowData(
                label: 'Slippage tolerance',
                value: '0.25 USDC (0.5%)',
              ),
              const SwapStatusDetailRowData(
                label: 'Guaranteed minimum',
                value: '0.249 ZEC',
              ),
              const SwapStatusDetailRowData(
                label: 'Timestamp',
                value: 'May 20',
              ),
              SwapStatusDetailRowData(
                label: 'Tx ID',
                value: '012312…4512',
                linkUri: Uri.parse(
                  'https://explorer.near-intents.org/?search=012312',
                ),
              ),
              const SwapStatusDetailRowData(
                label: 'Swap fee',
                value: 'Included',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('More details'), findsNothing);
    expect(find.text('Less details'), findsNothing);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Price protection'), findsNothing);
    expect(find.text('USDC recipient'), findsNothing);
    expect(find.text('USDC refund address'), findsNothing);
    expect(find.text('Swap fee'), findsNothing);
    expect(find.text('Deposit USDC to'), findsOneWidget);
    expect(find.text('Slippage tolerance'), findsOneWidget);
    expect(find.text('Guaranteed minimum'), findsOneWidget);
    expect(find.text('Memo'), findsOneWidget);
    expect(find.text('Missing deposit'), findsOneWidget);
    expect(find.text('Required deposit'), findsOneWidget);
    expect(find.text('Detected deposit'), findsOneWidget);
    expect(find.text('Deposit deadline'), findsOneWidget);
    expect(find.text('Refund fee'), findsOneWidget);
    expect(find.text('Timestamp'), findsOneWidget);
    expect(find.text('Tx ID'), findsOneWidget);
    expect(find.text('Tx fee'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.arrowTopRight,
      ),
      findsOneWidget,
    );

    final detailsRect = tester.getRect(
      find.byKey(const ValueKey('mobile_swap_transaction_details')),
    );
    final card = tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile_swap_status_card')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      card.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
    );
    final labelRect = tester.getRect(find.text('Slippage tolerance'));
    final valueRect = tester.getRect(find.text('0.25 USDC (0.5%)'));
    expect(labelRect.left, moreOrLessEquals(detailsRect.left));
    expect(valueRect.left, greaterThan(labelRect.right));
    expect(valueRect.right, greaterThan(detailsRect.right - 120));
  });

  testWidgets('completed details hide recipient and deposit address rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        SingleChildScrollView(
          child: _content(
            showTabs: false,
            badgeKind: SwapStatusBadgeKind.completed,
            details: [
              const SwapStatusDetailRowData(
                label: 'USDC recipient',
                value: '0x9aDF…Ef064',
                copyable: true,
                copyText: '0x9aDFd2310B3FA54A8718445c82Eb2ef1c19Ef064',
              ),
              const SwapStatusDetailRowData(
                label: 'ZEC deposit to',
                value: 't1WXCS…vy16c',
                copyable: true,
                copyText: 't1WXCSFXY2bSBydHrSFADJd4igsttkvy16c',
              ),
              const SwapStatusDetailRowData(
                label: 'Total fees',
                value: 'Included',
              ),
              SwapStatusDetailRowData(
                label: 'Tx ID',
                value: '0x9aDF…Ef064',
                linkUri: Uri.parse(
                  'https://explorer.near-intents.org/transactions/'
                  '0x9aDFd2310B3FA54A8718445c82Eb2ef1c19Ef064',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('USDC recipient'), findsNothing);
    expect(find.text('ZEC deposit to'), findsNothing);
    expect(find.text('Tx ID'), findsOneWidget);
    expect(find.text('Swap fee'), findsOneWidget);
    expect(find.text('Tx fee'), findsNothing);
  });
}

Finder _tooltipWithMessage(String message) {
  return find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == message,
  );
}
