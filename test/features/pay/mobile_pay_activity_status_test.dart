@Tags(['mobile'])
library;

import 'package:flutter/material.dart' show MaterialApp, Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/review_list_row.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_swap_activity_detail_screen.dart';
import 'package:zcash_wallet/src/features/address_book/providers/address_book_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_review_header.dart';
import 'package:zcash_wallet/src/features/swap/widgets/mobile/mobile_swap_status_content.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_activity_panel.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _recipient = '0x12351aBcDeF01234567890123456789076123';

Widget _harness(
  Widget child, {
  AppThemeData theme = AppThemeData.light,
  bool scroll = true,
}) {
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
              child: scroll ? SingleChildScrollView(child: child) : child,
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
    payStatus: PayActivityStatusPresentation(
      phase: completed
          ? PayActivityStatusPhase.completed
          : PayActivityStatusPhase.inProgress,
      timestampText: 'May 20, 2026 13:20',
      txIdText: '0123123124512512',
      txIdUri: Uri.parse('https://explorer.near-intents.org/transactions/1'),
      convertedFromText: '4.125 ZEC',
      transactionFeeText: '0.0001 ZEC',
    ),
    badgeKind: completed
        ? SwapStatusBadgeKind.completed
        : SwapStatusBadgeKind.liveQuote,
    progressIndex: completed ? 3 : 1,
    steps: const [],
    details: const [
      SwapStatusDetailRowData(
        label: 'Network + conversion fees',
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
    expect(find.text('0.0001 ZEC'), findsOneWidget);
    expect(find.text('0.0125 ZEC'), findsNothing);
    expect(_tooltipWithMessage(kTxFeeHelpTooltip), findsOneWidget);
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

    final statusLabel = tester.widget<Text>(find.text('Status'));
    final statusValue = tester.widget<Text>(find.text('In progress...'));
    expect(statusLabel.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(statusLabel.style?.fontWeight, AppTypography.labelLarge.fontWeight);
    expect(statusValue.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(statusValue.style?.fontWeight, FontWeight.w500);
    expect(statusValue.style?.color, AppThemeData.light.colors.text.primary);

    final statusRowRect = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_status_row')),
    );
    final statusValueRect = tester.getRect(
      find.byKey(const ValueKey('mobile_pay_status_value')),
    );
    expect(
      statusValueRect.right,
      closeTo(statusRowRect.right - AppSpacing.xxs, 0.01),
      reason: 'the icon and status copy must be pinned to the right edge',
    );

    final detailLabels = ['Timestamp', 'Tx ID', 'Converted from', 'Tx fee'];
    for (final label in detailLabels) {
      final labelText = tester.widget<Text>(find.text(label));
      expect(
        labelText.style?.fontSize,
        AppTypography.labelLarge.fontSize,
        reason: '$label should use the Pay detail label token',
      );
    }

    expect(
      tester.widget<AppIcon>(_appIcon(AppIcons.loader)).color,
      AppThemeData.light.colors.icon.regular,
    );
    expect(
      tester.widget<AppIcon>(_appIcon(AppIcons.arrowTopRight)).color,
      AppThemeData.light.colors.icon.muted,
    );
    expect(
      tester.widget<AppIcon>(_appIcon(AppIcons.shieldKeyhole)).color,
      AppThemeData.light.colors.icon.accent,
    );
    expect(
      tester.widget<AppIcon>(_appIcon(AppIcons.help)).color,
      AppThemeData.light.colors.icon.muted,
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

  test(
    'mobile pay keeps the confirmed deposit fee separate from route fees',
    () {
      final presentation = swapActivityStatusPresentationForIntent(
        _state(),
        _intent(status: SwapIntentStatus.processing),
        confirmedDepositFeeZatoshi: BigInt.from(10000),
      );

      expect(presentation.paymentMode, isTrue);
      expect(presentation.payStatus?.transactionFeeText, '0.0001 ZEC');
      expect(
        presentation.details.map((row) => row.label),
        contains('Network + conversion fees'),
      );
      expect(
        presentation.details.map((row) => row.label),
        isNot(contains('Tx fee')),
      );

      final withoutConfirmedDeposit = swapActivityStatusPresentationForIntent(
        _state(),
        _intent(status: SwapIntentStatus.processing),
      );
      expect(
        withoutConfirmedDeposit.payStatus?.transactionFeeText,
        'Not reported',
      );
    },
  );

  testWidgets(
    'mobile Pay loads the confirmed wallet deposit fee and Zcash tooltip',
    (tester) async {
      const depositTxid =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final intent = _intent(
        status: SwapIntentStatus.processing,
      ).copyWith(accountUuid: 'account-1', depositTxHash: depositTxid);
      final state = SwapState(
        direction: SwapDirection.zecToExternal,
        amountText: '',
        receiveAmountText: '',
        destinationText: '',
        externalAsset: SwapAsset.usdc,
        reviewVisible: false,
        intents: [intent],
        selectedIntentId: intent.id,
        payMode: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountProvider.overrideWith(_PayAccountNotifier.new),
            addressBookProvider.overrideWith(_EmptyAddressBookNotifier.new),
            swapStateProvider.overrideWith(() => _PayStatusNotifier(state)),
            syncProvider.overrideWith(
              () => FakeSyncNotifier(
                SyncState(
                  accountUuid: 'account-1',
                  hasAccountScopedData: true,
                  recentTransactions: [
                    _sentZecTransaction(
                      txidHex: depositTxid,
                      fee: BigInt.from(10000),
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: _harness(
            SwapActivityDetailPagePanel(
              state: state,
              intent: intent,
              layout: SwapActivityDetailLayout.mobile,
              depositChecking: false,
              depositCheckWarning: null,
              onRefreshStatus: () {},
              onMarkDeposited: () {},
              onDepositTxHashChanged: (_) {},
              onSubmitDepositTransaction: () {},
              onReviewFreshQuote: () {},
              onSignZecDeposit: (_) {},
              intentIsHardware: false,
            ),
            scroll: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('0.0001 ZEC'), findsOneWidget);
      expect(find.text('0.0125 ZEC'), findsNothing);
      expect(_tooltipWithMessage(kTxFeeHelpTooltip), findsOneWidget);
    },
  );

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

Finder _appIcon(String name) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == name,
    description: 'AppIcon($name)',
  );
}

Finder _tooltipWithMessage(String message) {
  return find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == message,
    description: 'Tooltip("$message")',
  );
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

rust_sync.TransactionInfo _sentZecTransaction({
  required String txidHex,
  required BigInt fee,
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: -412500000,
    fee: fee,
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'sent',
    displayAmount: BigInt.from(412500000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

class _PayStatusNotifier extends SwapNotifier {
  _PayStatusNotifier(this.initialState);

  final SwapState initialState;

  @override
  SwapState build() => initialState;
}

class _PayAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1payaccount',
  );
}

class _EmptyAddressBookNotifier extends AddressBookNotifier {
  @override
  AddressBookState build() => const AddressBookState();
}
