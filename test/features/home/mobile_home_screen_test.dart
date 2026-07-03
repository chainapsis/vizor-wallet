@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/privacy/privacy_mask.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zec_price_change_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

/// Skips the secure-storage write so toggling works without a platform
/// channel in widget tests.
class _FakePrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _FakeMarketDataSource implements ZecMarketDataSource {
  const _FakeMarketDataSource(this.data);

  final ZecMarketData? data;

  @override
  Future<ZecMarketData?> fetchMarketData() async => data;
}

TextStyle _effectiveTextStyle(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final defaultStyle = DefaultTextStyle.of(tester.element(finder)).style;
  return defaultStyle.merge(text.style);
}

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
  activeAddress: 'u1homeaddress',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home',
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

Widget _app(
  SyncState syncState, {
  ZecMarketData? marketData = const ZecMarketData(
    usdPrice: 70,
    change24hPct: 13.12,
  ),
  FakeSyncNotifier? syncNotifier,
}) {
  final effectiveSyncNotifier = syncNotifier ?? FakeSyncNotifier(syncState);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const MobileHomeScreen()),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(() => effectiveSyncNotifier),
      privacyModeProvider.overrideWith(_FakePrivacyModeNotifier.new),
      zecMarketDataSourceProvider.overrideWithValue(
        _FakeMarketDataSource(marketData),
      ),
    ],
    child: MaterialApp.router(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    ),
  );
}

SyncState _syncedState({
  BigInt? orchardBalance,
  BigInt? transparentBalance,
  bool canShieldTransparentBalance = false,
}) => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  percentage: 1.0,
  displayPercentage: 1.0,
  orchardBalance: orchardBalance ?? BigInt.zero,
  transparentBalance: transparentBalance ?? BigInt.zero,
  canShieldTransparentBalance: canShieldTransparentBalance,
);

rust_sync.TransactionInfo _tx(int index) {
  final seconds = BigInt.from(1800000000 + index);
  return rust_sync.TransactionInfo(
    txidHex: 'tx-$index',
    minedHeight: BigInt.from(index),
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: seconds,
    isTransparent: false,
    txKind: 'received',
    displayAmount: BigInt.from(index) * BigInt.from(100000000),
    displayPool: 'shielded',
    createdTime: seconds,
  );
}

void main() {
  testWidgets('shows the importing state before account data exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        SyncState(
          accountUuid: 'account-1',
          isSyncing: true,
          displayPercentage: 0.32,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('32%'), findsOneWidget);
    expect(find.textContaining("importing"), findsOneWidget);
    expect(find.text('Send'), findsNothing);

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_canvas')),
    );
    final imageRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_image')),
    );

    expect(canvasRect.size, const Size(340, 220));
    expect(imageRect.size, const Size(246, 192));
    expect(canvasRect.bottom, moreOrLessEquals(744));
  });

  testWidgets('shows balance, actions, and empty activity when funded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('143.12', findRichText: true), findsOneWidget);
    expect(find.text(r'$10.02K'), findsOneWidget);
    expect(find.text('+ 13.12% (24h)'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('No activity, yet...'), findsOneWidget);
  });

  testWidgets('shows transparent balance tray with shield action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(14312000000),
          transparentBalance: BigInt.from(242000000),
          canShieldTransparentBalance: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mobile_home_transparent_balance_strip')),
      findsOneWidget,
    );
    expect(find.text('Transparent: 2.42 ZEC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_home_shield_balance_button')),
      findsOneWidget,
    );
    expect(find.text('Shield'), findsOneWidget);
  });

  testWidgets('animates transparent balance tray away before removal', (
    tester,
  ) async {
    final syncNotifier = FakeSyncNotifier(
      _syncedState(
        orchardBalance: BigInt.from(14312000000),
        transparentBalance: BigInt.from(242000000),
        canShieldTransparentBalance: true,
      ),
    );
    await tester.pumpWidget(
      _app(syncNotifier.initialState!, syncNotifier: syncNotifier),
    );
    await tester.pump();
    await tester.pump();

    final stripFinder = find.byKey(
      const ValueKey('mobile_home_transparent_balance_strip'),
    );
    expect(stripFinder, findsOneWidget);
    final expandedHeight = tester.getSize(stripFinder).height;
    expect(expandedHeight, moreOrLessEquals(57));

    syncNotifier.setSyncState(
      _syncedState(orchardBalance: BigInt.from(14312000000)),
    );
    await tester.pump();
    expect(stripFinder, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 70));
    expect(tester.getSize(stripFinder).height, lessThan(expandedHeight));

    await tester.pumpAndSettle();
    expect(stripFinder, findsNothing);
  });

  testWidgets('matches the Figma balance card controls and action labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();
    await tester.pump();

    final privacyButtonRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_privacy_button')),
    );
    final privacyIcon = tester.widget<AppIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile_home_privacy_button')),
        matching: find.byType(AppIcon),
      ),
    );
    final sendRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_send')),
    );
    final sendLabelStyle = _effectiveTextStyle(tester, find.text('Send'));
    final receiveLabelStyle = _effectiveTextStyle(tester, find.text('Receive'));
    final shieldedLabel = tester.widget<Text>(find.text('Shielded balance'));
    final fiatLabel = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_home_balance_fiat_text')),
    );
    final balanceText = tester.widget<Text>(
      find.byKey(const ValueKey('mobile_home_shielded_balance')),
    );
    final balanceSpan = balanceText.textSpan! as TextSpan;
    final amountSpan = balanceSpan.children![0] as TextSpan;
    final tickerSpan = balanceSpan.children![1] as TextSpan;

    expect(privacyButtonRect.size, const Size(32, 32));
    expect(privacyIcon.size, 16);
    expect(sendRect.height, AppButtonSizing.largeHeight);
    expect(sendLabelStyle.fontSize, AppTypography.labelLarge.fontSize);
    expect(sendLabelStyle.height, AppTypography.labelLarge.height);
    expect(sendLabelStyle.fontWeight, AppTypography.labelLarge.fontWeight);
    expect(
      sendLabelStyle.letterSpacing,
      AppTypography.labelLarge.letterSpacing,
    );
    expect(receiveLabelStyle.fontSize, AppTypography.labelLarge.fontSize);
    expect(receiveLabelStyle.height, AppTypography.labelLarge.height);
    expect(receiveLabelStyle.fontWeight, AppTypography.labelLarge.fontWeight);
    expect(
      receiveLabelStyle.letterSpacing,
      AppTypography.labelLarge.letterSpacing,
    );
    expect(shieldedLabel.style?.fontSize, 14);
    expect(shieldedLabel.style?.height, 16 / 14);
    expect(fiatLabel.style?.fontSize, 14);
    expect(amountSpan.style?.fontSize, 45);
    expect(amountSpan.style?.height, 48 / 45);
    expect(tickerSpan.style?.fontSize, 32);
    expect(tickerSpan.style?.height, 33 / 32);
  });

  testWidgets('zero balance offers the first-receive action', (tester) async {
    await tester.pumpWidget(_app(_syncedState()));
    await tester.pump();

    expect(find.text('Receive your first ZEC'), findsOneWidget);
    expect(find.text('Send'), findsNothing);

    await tester.tap(find.text('Receive your first ZEC'));
    await tester.pumpAndSettle();
    expect(find.text('receive route'), findsOneWidget);
  });

  testWidgets('uses the mobile Rest illustration canvas for empty activity', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_app(_syncedState()));
    await tester.pump();

    final canvasRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_canvas')),
    );
    final imageRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_rest_image')),
    );

    expect(canvasRect.size, const Size(340, 220));
    expect(imageRect.size, const Size(246, 192));
    expect(imageRect.left - canvasRect.left, 47);
    expect(imageRect.top - canvasRect.top, 28);
  });

  testWidgets('privacy eye masks the balance', (tester) async {
    final impactTypes = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          impactTypes.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.eye,
      ),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Hide balance'));
    await tester.pump();

    expect(
      find.textContaining(fixedPrivacyMask(), findRichText: true),
      findsAtLeastNWidgets(2),
    );
    expect(impactTypes, ['HapticFeedbackType.mediumImpact']);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.eyeClosed,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('143.12', findRichText: true), findsNothing);
    expect(find.text(r'$10.02K'), findsNothing);
  });

  testWidgets('shows up to ten recent activity rows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        _syncedState(orchardBalance: BigInt.from(100000000)).copyWith(
          recentTransactions: [for (var i = 0; i < 11; i++) _tx(i + 1)],
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 10; i++) {
      expect(
        find.byKey(ValueKey('mobile_home_activity_row_$i')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey('mobile_home_activity_row_10')),
      findsNothing,
    );
  });

  testWidgets('recent activity section uses the Figma inner inset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _app(
        _syncedState(
          orchardBalance: BigInt.from(100000000),
        ).copyWith(recentTransactions: [_tx(1)]),
      ),
    );
    await tester.pump();

    final sendRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_send')),
    );
    final receiveRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_receive')),
    );
    final rowRect = tester.getRect(
      find.byKey(const ValueKey('mobile_home_activity_row_0')),
    );
    final headerFinder = find.text('Recent activity');
    final seeAllFinder = find.text('See all');
    final headerRect = tester.getRect(headerFinder);
    final seeAllRect = tester.getRect(
      find.ancestor(
        of: seeAllFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 24,
        ),
      ),
    );
    final headerText = tester.widget<Text>(headerFinder);
    final seeAllText = tester.widget<Text>(seeAllFinder);

    expect(rowRect.left, sendRect.left + AppSpacing.xs);
    expect(rowRect.right, receiveRect.right - AppSpacing.xs);
    expect(headerRect.left, rowRect.left);
    expect(seeAllRect.height, 24);
    expect(headerText.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(headerText.style?.fontWeight, FontWeight.w600);
    expect(seeAllText.style?.fontSize, AppTypography.labelLarge.fontSize);
    expect(
      seeAllText.style?.color,
      AppThemeData.dark.colors.button.ghost.label,
    );
  });
}
