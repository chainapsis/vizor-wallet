import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  testWidgets(
    'shows the no-activity home state when account history is empty',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _homeHarness(
          SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No activity, yet...'), findsOneWidget);
      expect(find.text('How about running your first ZEC tx?'), findsOneWidget);
      expect(find.text('Recent Activity'), findsNothing);
      expect(find.text('Receive your first ZEC'), findsOneWidget);
    },
  );

  testWidgets('does not show the no-activity state while history is loading', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_homeHarness(SyncState()));
    await tester.pump();
    await tester.pump();

    expect(find.text('No activity, yet...'), findsNothing);
    expect(find.text('Loading activity...'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);
  });

  testWidgets('shows compact recent activity rows when history is present', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _homeHarness(
        SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          orchardBalance: BigInt.from(150000000),
          recentTransactions: [
            _tx(
              txidHex: '01',
              txKind: 'received',
              displayAmount: BigInt.from(46000000),
            ),
            _tx(
              txidHex: '02',
              txKind: 'sent',
              displayAmount: BigInt.from(10000000),
            ),
            _tx(
              txidHex: '03',
              txKind: 'shielded',
              displayAmount: BigInt.from(985000),
            ),
            _tx(
              txidHex: '04',
              txKind: 'receiving',
              displayAmount: BigInt.from(1000000),
              minedHeight: BigInt.zero,
              blockTime: BigInt.zero,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No activity, yet...'), findsNothing);
    expect(find.text('Recent Activity'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('0.00985 ZEC'), findsOneWidget);
    expect(find.text('Receiving ...'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('home_recent_activity_row_0'))),
      const Size(364, 44),
    );
  });
}

Widget _homeHarness(SyncState syncState) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive route')),
      GoRoute(
        path: '/activity',
        builder: (_, _) => const Text('activity route'),
      ),
      GoRoute(
        path: '/settings/endpoint',
        builder: (_, _) => const Text('endpoint route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      syncProvider.overrideWith(() => _FakeSyncNotifier(syncState)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Primary Vault',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1homeaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}

rust_sync.TransactionInfo _tx({
  required String txidHex,
  required String txKind,
  required BigInt displayAmount,
  BigInt? minedHeight,
  BigInt? blockTime,
}) {
  final resolvedMinedHeight = minedHeight ?? BigInt.from(100);
  final resolvedBlockTime = blockTime ?? BigInt.from(1717000000);
  return rust_sync.TransactionInfo(
    txidHex: txidHex,
    minedHeight: resolvedMinedHeight,
    expiredUnmined: false,
    accountBalanceDelta: 0,
    fee: BigInt.zero,
    blockTime: resolvedBlockTime,
    isTransparent: false,
    txKind: txKind,
    displayAmount: displayAmount,
    displayPool: 'shielded',
    createdTime: resolvedBlockTime,
  );
}
