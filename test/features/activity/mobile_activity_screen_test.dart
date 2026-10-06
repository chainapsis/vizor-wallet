@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_activity_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/mobile/mobile_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/activity/activity_eta_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../support/wallet_path_read_blocker.dart';

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
  Map<String, String>? etaLabels,
  FakeSyncNotifier? syncNotifier,
  SwapActivityStore? swapActivityStore,
  GiftCardActivityIndex giftCardActivityIndex = GiftCardActivityIndex.empty,
  GoRouter? router,
}) {
  return ProviderScope(
    overrides: [
      if (etaLabels != null)
        activityEtaLabelsProvider.overrideWithValue(etaLabels),
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(
        () =>
            syncNotifier ??
            FakeSyncNotifier(
              SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
            ),
      ),
      if (swapActivityStore != null)
        swapActivityStoreProvider.overrideWithValue(swapActivityStore),
      giftCardActivityIndexProvider.overrideWith((ref, accountUuid) async {
        return giftCardActivityIndex;
      }),
    ],
    child: router != null
        ? MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.dark, child: child!),
          )
        : MaterialApp(
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
  testWidgets(
    'same-epoch failed history refresh withholds ETA until recovery',
    (tester) async {
      final pending = _tx(
        txidHex: 'pending',
        blockTime: BigInt.zero,
        minedHeight: BigInt.zero,
        kind: 'sent',
      );
      final before = SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
        lastSyncCompletedAt: DateTime.utc(2026, 10, 6),
      );
      final sync = FakeSyncNotifier(before);
      final refreshing = Completer<List<rust_sync.TransactionInfo>>();
      var reads = 0;
      var isRefreshing = false;
      await tester.pumpWidget(
        _app(
          (_) async {
            reads++;
            return isRefreshing ? refreshing.future : [pending];
          },
          syncNotifier: sync,
          etaLabels: const {'pending': 'Est. 1–3 min'},
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Est. 1–3 min'), findsOneWidget);
      final initialReads = reads;
      isRefreshing = true;
      sync.emit(before.copyWith(recentTransactions: [pending]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(reads, initialReads + 1);
      expect(find.text('Est. 1–3 min'), findsOneWidget);
      expect(find.text('Checking status'), findsNothing);
      refreshing.completeError(StateError('history unavailable'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Est. 1–3 min'), findsNothing);
      isRefreshing = false;
      sync.emit(before.copyWith(recentTransactions: []));
      await tester.pump(const Duration(milliseconds: 300));
      expect(reads, initialReads + 2);
      expect(find.text('Est. 1–3 min'), findsOneWidget);
    },
  );

  for (final newBlock in [false, true]) {
    testWidgets(
      'sync completion refreshes older history (new block: $newBlock)',
      (tester) async {
        final before = SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          lastSyncCompletedAt: DateTime.utc(2026, 10, 6),
        );
        final sync = FakeSyncNotifier(before);
        var reads = 0;
        var refreshing = false;
        final refreshed = Completer<List<rust_sync.TransactionInfo>>();
        await tester.pumpWidget(
          _app(
            (_) async {
              reads++;
              if (!refreshing) {
                return [
                  _tx(
                    txidHex: 'old-pending',
                    blockTime: BigInt.zero,
                    minedHeight: BigInt.zero,
                    kind: 'sent',
                  ),
                ];
              }
              return refreshed.future;
            },
            syncNotifier: sync,
            etaLabels: const {'old-pending': 'Est. 1–3 min'},
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Est. 1–3 min'), findsOneWidget);
        final initialReads = reads;
        refreshing = true;
        // The recent-ten history is unchanged (empty); this older transaction mined.
        sync.emit(
          before.copyWith(
            scannedHeight: newBlock ? 101 : before.scannedHeight,
            chainTipHeight: newBlock ? 101 : before.chainTipHeight,
            lastSyncCompletedAt: DateTime.utc(2026, 10, 6, 0, 1),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(reads, initialReads + 1);
        expect(find.text('Est. 1–3 min'), findsNothing);
        expect(find.text('Checking status'), findsOneWidget);
        refreshed.complete([
          _tx(
            txidHex: 'old-pending',
            blockTime: BigInt.from(1800000000),
            kind: 'sent',
          ),
        ]);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text('Sent'), findsOneWidget);
        expect(find.text('Est. 1–3 min'), findsNothing);
      },
    );
  }

  testWidgets('ETA and status subtitles fit a standard mobile activity row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))).load();
    final labels = [
      'Est. 1–3 min',
      'Est. 2–6 min',
      'Taking longer',
      'Checking status',
      'Waiting for connection',
    ];
    await tester.pumpWidget(
      _app(
        (_) async => [
          for (var i = 0; i < labels.length; i++)
            _tx(
              txidHex: 'pending-$i',
              blockTime: BigInt.zero,
              minedHeight: BigInt.zero,
              kind: 'sent',
            ),
        ],
        etaLabels: {
          for (var i = 0; i < labels.length; i++) 'pending-$i': labels[i],
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    for (final label in labels) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity replaces the pending pool with ETA', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        (_) async => [
          _tx(
            txidHex: 'pending',
            blockTime: BigInt.zero,
            minedHeight: BigInt.zero,
            kind: 'sent',
          ),
          _tx(txidHex: 'mined', blockTime: BigInt.from(1800000000)),
        ],
        etaLabels: const {'pending': 'Est. 1–3 min', 'mined': 'Est. 1–3 min'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sending...'), findsOneWidget);
    expect(find.text('Est. 1–3 min'), findsOneWidget);
    expect(find.text('Shielded'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity tap opens before receipt loading completes', (
    tester,
  ) async {
    final history = Completer<List<rust_sync.TransactionInfo>>();
    final tx = _tx(txidHex: 'a' * 64, blockTime: BigInt.from(1764150000));
    MobileTransactionStatusArgs? suppliedArgs;
    await tester.binding.setSurfaceSize(const Size(393, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(
          path: '/activity',
          builder: (_, _) =>
              MobileActivityScreen(historyLoader: (_) async => [tx]),
        ),
        GoRoute(
          path: '/activity/tx/:txid',
          builder: (_, state) {
            suppliedArgs = state.extra as MobileTransactionStatusArgs;
            return MobileTransactionStatusScreen(
              args: suppliedArgs!,
              historyLoader: (_) => history.future,
              detailLoader: (_, _) async => null,
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app((_) async => [tx], router: router));
    await tester.pumpAndSettle();
    WalletPathReadBlocker();
    await tester.tap(find.text('Received'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(MobileTransactionStatusScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MobileTransactionStatusScreen),
        matching: find.text('Received'),
      ),
      findsOneWidget,
    );
    expect(history.isCompleted, isFalse);
    expect(suppliedArgs!.sourceAccountUuid, 'account-1');
    expect(suppliedArgs!.initialTransaction, same(tx));
    expect(suppliedArgs!.initialDetail, isNull);
  });

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

  testWidgets('renders Gift Card creation and redemption rows', (tester) async {
    await tester.pumpWidget(
      _app(
        (_) async => [
          _tx(txidHex: 'gift-redeemed', blockTime: BigInt.from(1800000001)),
          _tx(
            txidHex: 'gift-created',
            blockTime: BigInt.from(1800000000),
            kind: 'sent',
          ),
        ],
        giftCardActivityIndex: GiftCardActivityIndex(
          createdTxids: const {'gift-created'},
          redeemedTxids: const {'gift-redeemed'},
          createdMetadataByTxid: {
            'gift-created': GiftCardActivityMetadata(
              claimFeeReserveZatoshi: BigInt.from(10000),
              kind: GiftCardActivityKind.created,
              amountZatoshi: BigInt.from(50000000),
              artworkId: 'ruby',
              message: 'Happy birthday!',
            ),
          },
          redeemedMetadataByTxid: {
            'gift-redeemed': GiftCardActivityMetadata(
              kind: GiftCardActivityKind.redeemed,
              amountZatoshi: BigInt.from(30000000),
              artworkId: 'crystal',
              message: null,
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Redeemed a gift card'), findsOneWidget);
    expect(find.text('Created a gift card'), findsOneWidget);
    // The card amount, not the funding total the transaction carries.
    expect(find.text('-0.5 ZEC'), findsOneWidget);
    expect(find.text('+0.3 ZEC'), findsOneWidget);
    expect(find.text('-1 ZEC'), findsNothing);
    expect(find.text('+1 ZEC'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.giftCard,
      ),
      findsNWidgets(2),
    );
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
