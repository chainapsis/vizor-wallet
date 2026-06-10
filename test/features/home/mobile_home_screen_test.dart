@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/privacy/privacy_mask.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_home_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

/// Skips the secure-storage write so toggling works without a platform
/// channel in widget tests.
class _FakePrivacyModeNotifier extends PrivacyModeNotifier {
  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
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

Widget _app(SyncState syncState) {
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
      syncProvider.overrideWith(() => FakeSyncNotifier(syncState)),
      privacyModeProvider.overrideWith(_FakePrivacyModeNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    ),
  );
}

SyncState _syncedState({BigInt? orchardBalance}) => SyncState(
  accountUuid: 'account-1',
  hasAccountScopedData: true,
  percentage: 1.0,
  displayPercentage: 1.0,
  orchardBalance: orchardBalance ?? BigInt.zero,
);

void main() {
  testWidgets('shows the importing state before account data exists', (
    tester,
  ) async {
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
  });

  testWidgets('shows balance, actions, and empty activity when funded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();

    expect(find.textContaining('143.12', findRichText: true), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);
    expect(find.text('No activity, yet...'), findsOneWidget);
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

  testWidgets('privacy eye masks the balance', (tester) async {
    await tester.pumpWidget(
      _app(_syncedState(orchardBalance: BigInt.from(14312000000))),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Hide balance'));
    await tester.pump();

    expect(
      find.textContaining(fixedPrivacyMask(), findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('143.12', findRichText: true), findsNothing);
  });
}
