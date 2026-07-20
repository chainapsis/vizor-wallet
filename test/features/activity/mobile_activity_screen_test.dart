@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1activityaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/activity',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

rust_sync.TransactionInfo _tx({
  required String txidHex,
  required BigInt blockTime,
  String kind = 'received',
  BigInt? minedHeight,
  bool expiredUnmined = false,
  BigInt? displayAmount,
  String displayPool = 'shielded',
}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: minedHeight ?? BigInt.one,
    expiredUnmined: expiredUnmined,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: blockTime,
    isTransparent: false,
    txKind: kind,
    displayAmount: displayAmount ?? BigInt.from(100000000),
    displayPool: displayPool,
    createdTime: blockTime,
  );
}

SwapIntentRecord _payActivityRecord({
  required String id,
  required String depositTxHash,
}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '0.1954 ZEC',
    receiveEstimateText: '100 USDC',
    status: SwapIntentStatus.processing,
    nextAction: 'Payment in progress',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1paydeposit',
    depositTxHash: depositTxHash,
    providerQuoteId: 'quote-$id',
    accountUuid: 'account-1',
    payMode: true,
    lastStatusCheckedAt: DateTime.now().toUtc(),
    createdAt: DateTime.utc(2026, 7, 20, 10),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
  );
}

Widget _app(
  MobileActivityHistoryLoader loader, {
  SwapActivityStore? swapActivityStore,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      ),
      if (swapActivityStore != null)
        swapActivityStoreProvider.overrideWithValue(swapActivityStore),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: MobileActivityScreen(historyLoader: loader),
      ),
    ),
  );
}

class _FakeSwapActivityStore implements SwapActivityStore {
  const _FakeSwapActivityStore(this.records);

  final List<SwapIntentRecord> records;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return [
      for (final record in records)
        if (record.accountUuid == accountUuid) record,
    ];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {}

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {}
}

void main() {
  testWidgets('groups loaded history into dated sections', (tester) async {
    final now = DateTime.now();
    final thisWeek = BigInt.from(now.millisecondsSinceEpoch ~/ 1000 - 60);
    // Stable "earlier month" timestamp ~70 days back.
    final older = BigInt.from(
      now.subtract(const Duration(days: 70)).millisecondsSinceEpoch ~/ 1000,
    );

    await tester.pumpWidget(
      _app(
        (_) async => [
          _tx(txidHex: 'aa', blockTime: thisWeek),
          _tx(txidHex: 'bb', blockTime: older, kind: 'sent'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.chevronBackward &&
            widget.size == 24,
      ),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mobile_activity_feed'))).dy,
      moreOrLessEquals(kMobileTopNavHeight + AppSpacing.s),
    );
    expect(find.text('This week'), findsOneWidget);
    // The older entry lands in a month-year section.
    final olderDate = now.subtract(const Duration(days: 70));
    expect(find.textContaining('${olderDate.year}'), findsOneWidget);
  });

  testWidgets('absorbs a Pay deposit transaction into the payment row', (
    tester,
  ) async {
    const depositDisplayOrder =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    await tester.pumpWidget(
      _app(
        (_) async => [
          _tx(
            txidHex: depositWalletOrder,
            blockTime: BigInt.from(1800000000),
            kind: 'sent',
            minedHeight: BigInt.zero,
            displayAmount: BigInt.from(19540000),
            displayPool: 'transparent',
          ),
        ],
        swapActivityStore: _FakeSwapActivityStore([
          _payActivityRecord(
            id: 'pay-mobile-dedupe',
            depositTxHash: depositDisplayOrder,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment in progress'), findsOneWidget);
    expect(find.text('100 USDC'), findsOneWidget);
    expect(find.text('Sending...'), findsNothing);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('Transparent'), findsNothing);
  });

  testWidgets('shows the empty state when history is empty', (tester) async {
    await tester.pumpWidget(_app((_) async => []));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('mobile_activity_feed'))).dy,
      moreOrLessEquals(kMobileTopNavHeight + AppSpacing.s),
    );
    expect(find.text('No activity yet'), findsOneWidget);
  });

  testWidgets('surfaces a friendly error when loading fails', (tester) async {
    await tester.pumpWidget(
      _app((_) async => throw StateError('db unavailable')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't load activity. Try again in a moment."),
      findsOneWidget,
    );
  });
}
