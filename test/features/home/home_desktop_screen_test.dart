import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/features/receive/screens/receive_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_provider_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  // Render with the real app fonts instead of the square-glyph test font.
  // The test font is much wider than Geist/Young Serif, which overflows the
  // balance row in ways the running app does not.
  setUpAll(() async {
    final fonts = <String, List<String>>{
      'Geist': [
        'assets/fonts/Geist-Regular.ttf',
        'assets/fonts/Geist-Medium.ttf',
        'assets/fonts/Geist-SemiBold.ttf',
        'assets/fonts/Geist-Bold.ttf',
      ],
      'Young Serif': [
        'assets/fonts/YoungSerif-Regular.ttf',
      ],
    };
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final asset in entry.value) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  });
  testWidgets(
    'home privacy mode masks desktop balance without duplicate ticker',
    (tester) async {
      await tester.pumpWidget(
        _appHarness(
          '/home',
          privacyModeEnabled: true,
          syncState: SyncState(
            accountUuid: 'account-1',
            hasAccountScopedData: true,
            orchardBalance: BigInt.from(14_312_000_000),
            spendableBalance: BigInt.from(14_312_000_000),
            totalBalance: BigInt.from(14_312_000_000),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('******'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('home_desktop_balance_fiat_text')),
        findsOneWidget,
      );
      expect(find.text('ZEC'), findsOneWidget);
      expect(find.text('****** ZEC ZEC'), findsNothing);
    },
  );

  testWidgets('home desktop shows fiat balance when pricing is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home_desktop_balance_fiat_text')),
      findsOneWidget,
    );
    expect(find.text(r'$10.02K'), findsOneWidget);

    final colors = AppThemeData.light.colors;
    final fiatText = tester.widget<Text>(
      find.byKey(const ValueKey('home_desktop_balance_fiat_text')),
    );
    expect(fiatText.style?.color, colors.text.homeCard.withValues(alpha: 0.80));

    final shieldIcon = tester.widget<AppIcon>(
      find.byKey(const ValueKey('home_desktop_shielded_balance_icon')),
    );
    expect(shieldIcon.color, colors.text.homeCard);
  });

  testWidgets('home desktop content tracks pane center on scaled screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 864);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final contentFinder = find.byKey(const ValueKey('home_desktop_content'));
    final contentCenter = tester.getCenter(contentFinder).dx;
    final contentTop = tester.getTopLeft(contentFinder).dy;
    const shellPadding = 8.0;
    const sidebarWidth = 256.0;
    const sidebarGap = 8.0;
    const viewportWidth = 1400.0;
    const viewportHeight = 864.0;
    const paneLeft = shellPadding + sidebarWidth + sidebarGap;
    const paneWidth =
        viewportWidth - (shellPadding * 2) - sidebarWidth - sidebarGap;
    const paneCenter = paneLeft + (paneWidth / 2);
    const paneHeight = viewportHeight - (shellPadding * 2);
    const referencePaneHeight = 704.0;
    const referenceContentTop = 48.0;
    const expectedContentTop =
        shellPadding +
        referenceContentTop +
        ((paneHeight - referencePaneHeight) / 2);

    expect(contentCenter, moreOrLessEquals(paneCenter, epsilon: 0.1));
    expect(contentTop, moreOrLessEquals(expectedContentTop, epsilon: 0.1));
  });

  testWidgets('home desktop send action opens send screen', (tester) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home_desktop_send_button')));
    await _pumpUntilPresent(tester, find.byType(SendScreen));

    expect(find.byType(SendScreen), findsOneWidget);
  });

  testWidgets('home desktop receive action opens receive screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home_desktop_receive_button')));
    await _pumpUntilPresent(tester, find.byType(ReceiveScreen));

    expect(find.byType(ReceiveScreen), findsOneWidget);
  });

  testWidgets('home desktop see all action opens activity screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(id: 'swap-see-all'),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    await tester.tap(
      find.byKey(const ValueKey('home_desktop_activity_see_all_button')),
    );
    await _pumpUntilPresent(tester, find.byType(ActivityScreen));

    expect(find.byType(ActivityScreen), findsOneWidget);
  });

  testWidgets('home recent activity suppresses the swap-leg Sent duplicate', (
    tester,
  ) async {
    const depositDisplayOrder =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          recentTransactions: [_sentZecTx(txidHex: depositWalletOrder)],
        ),
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(
            id: 'swap-home-dedupe',
            depositTxHash: depositDisplayOrder,
          ),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    // The in-flight swap row already carries the signed outgoing amount, so
    // Home hides the standalone Sent broadcast row like the Activity screen.
    expect(find.text('Sent'), findsNothing);
  });

  testWidgets('home recent activity keeps the Sent row for refunded swaps', (
    tester,
  ) async {
    const depositDisplayOrder =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final depositWalletOrder = swapChainTxidToWalletTxidHex(
      depositDisplayOrder,
    )!;

    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          recentTransactions: [_sentZecTx(txidHex: depositWalletOrder)],
        ),
        swapActivityStore: _FakeSwapActivityStore([
          _swapActivityRecord(
            id: 'swap-home-refunded',
            status: SwapIntentStatus.refunded,
            depositTxHash: depositDisplayOrder,
          ),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swap failed'));

    // Refunded rows render unsigned, so the standalone Sent row stays.
    expect(find.text('Sent'), findsOneWidget);
  });

  testWidgets('home desktop shows transparent balance shield action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          transparentBalance: BigInt.from(242_000_000),
          canShieldTransparentBalance: true,
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_554_000_000),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home_desktop_transparent_balance_strip')),
      findsOneWidget,
    );
    expect(find.text('Transparent balance: 2.42 ZEC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home_shield_balance_button')),
      findsOneWidget,
    );
    expect(find.text('Shield balance'), findsOneWidget);
  });

  testWidgets('home desktop keeps recovery notice visible', (tester) async {
    await tester.pumpWidget(
      _appHarness('/home', passwordRotationRecoveryFailed: true),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_notice_card')), findsOneWidget);
    expect(
      find.text(
        "We couldn't verify the previous password change. Try again or restart Vizor.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('home desktop keeps sync failure notice visible', (tester) async {
    await tester.pumpWidget(
      _appHarness(
        '/home',
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          failure: const SyncFailure(
            kind: SyncFailureKind.network,
            rawMessage: 'network failed',
            userMessage: 'Network connection lost.',
            showSettingsAction: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home_notice_card')), findsOneWidget);
    expect(find.text('Network connection lost.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('home desktop scrolls notice and activity together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _appHarness(
        '/home',
        swapEnabled: true,
        passwordRotationRecoveryFailed: true,
        syncState: SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(14_312_000_000),
          spendableBalance: BigInt.from(14_312_000_000),
          totalBalance: BigInt.from(14_312_000_000),
        ),
        swapActivityStore: _FakeSwapActivityStore([
          for (var index = 0; index < 5; index++)
            _swapActivityRecord(id: 'swap-scroll-$index'),
        ]),
      ),
    );
    await _pumpUntilPresent(tester, find.text('Swapping...'));

    final scrollViewFinder = find.byKey(
      const ValueKey('home_desktop_scroll_view'),
    );
    final scrollableFinder = find.descendant(
      of: scrollViewFinder,
      matching: find.byType(Scrollable),
    );
    final scrollableState = tester.state<ScrollableState>(scrollableFinder);

    expect(tester.getSize(scrollViewFinder).width, greaterThan(420));
    expect(find.byKey(const ValueKey('home_notice_card')), findsOneWidget);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0));

    await tester.drag(scrollViewFinder, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0));
  });
}

SwapIntentRecord _swapActivityRecord({
  required String id,
  SwapIntentStatus status = SwapIntentStatus.processing,
  String? depositTxHash,
}) {
  return SwapIntentRecord(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1.0000 ZEC',
    receiveEstimateText: '70.170000 USDC',
    status: status,
    nextAction: status.label,
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1home-deposit',
    depositTxHash: depositTxHash,
    providerQuoteId: 'quote-$id',
    accountUuid: 'account-1',
    createdAt: DateTime.utc(2026, 5, 22, 10),
    updatedAt: DateTime.utc(2026, 5, 22, 10),
  );
}

rust_sync.TransactionInfo _sentZecTx({required String txidHex}) {
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: BigInt.from(2000000),
    expiredUnmined: false,
    accountBalanceDelta: -100000000,
    fee: BigInt.from(15000),
    blockTime: BigInt.from(1800000000),
    isTransparent: false,
    txKind: 'sent',
    displayAmount: BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: BigInt.from(1800000000),
  );
}

Widget _appHarness(
  String initialLocation, {
  bool? swapEnabled,
  bool privacyModeEnabled = false,
  bool passwordRotationRecoveryFailed = false,
  SyncState? syncState,
  SwapActivityStore? swapActivityStore,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(
          initialLocation,
          privacyModeEnabled: privacyModeEnabled,
          passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
        ),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(syncState ?? _syncedSyncState),
      ),
      if (swapEnabled != null)
        swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
      swapIntentProvider.overrideWithValue(const _FakeSwapProvider()),
      if (swapActivityStore != null)
        swapActivityStoreProvider.overrideWithValue(swapActivityStore),
    ],
    child: const ZcashWalletApp(),
  );
}

Future<void> _pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

AppBootstrapState _bootstrap(
  String initialLocation, {
  required bool privacyModeEnabled,
  required bool passwordRotationRecoveryFailed,
}) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(
      accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1testaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: privacyModeEnabled,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
  );
}

final _syncedSyncState = SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
);

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

class _FakeSwapProvider implements SwapProvider, SwapPricingProvider {
  const _FakeSwapProvider();

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return const [SwapAsset.usdc];
  }

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    return SwapPricingSnapshot(
      usdPrices: {SwapAsset.zec: 70, SwapAsset.usdc: 1},
    );
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(String intentId, {String? depositMemo}) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) {
    throw UnimplementedError();
  }
}
