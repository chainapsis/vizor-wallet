@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

AccountInfo _account(String uuid, String name, {bool isSeedAnchor = false}) =>
    AccountInfo(
      uuid: uuid,
      name: name,
      order: 0,
      profilePictureId: kDefaultProfilePictureId,
      isSeedAnchor: isSeedAnchor,
    );

AppBootstrapState _bootstrap(AccountState accounts) => AppBootstrapState(
  initialLocation: '/accounts',
  initialAccountState: accounts,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

Widget _app(AccountState accounts) {
  final router = GoRouter(
    initialLocation: '/accounts',
    routes: [
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const MobileAccountsScreen(),
      ),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account route'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(accounts)),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1200)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('groups the active account under Current and the rest under '
      'Other', (tester) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Knight'), findsOneWidget);
    expect(find.text('Viking'), findsOneWidget);
  });

  testWidgets('imported accounts offer removal; the last seed anchor does '
      'not', (tester) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    // Imported account: edit + remove.
    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_b')));
    await tester.pumpAndSettle();
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Sole seed anchor: edit only.
    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_a')));
    await tester.pumpAndSettle();
    expect(find.text('Edit account'), findsOneWidget);
    expect(find.text('Remove account'), findsNothing);
  });

  testWidgets('the edit sheet shows the avatar picker and validates the '
      'name', (tester) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [_account('a', 'Knight', isSeedAnchor: true)],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit account'));
    await tester.pumpAndSettle();

    expect(find.text('Account name'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_account_edit_avatar')));
    await tester.pumpAndSettle();
    expect(find.text('Select profile picture'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_account_pfp_update')));
    await tester.pumpAndSettle();
    expect(find.text('Select profile picture'), findsNothing);

    // Empty name is rejected in place.
    await tester.enterText(
      find.byKey(const ValueKey('mobile_account_edit_name')),
      '   ',
    );
    await tester.tap(find.byKey(const ValueKey('mobile_account_edit_save')));
    await tester.pump();
    expect(find.text('Account name'), findsOneWidget);
  });

  testWidgets('add account routes to the add-account flow', (tester) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [_account('a', 'Knight', isSeedAnchor: true)],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey('mobile_accounts_add_account'));
    expect(button, findsOneWidget);
    expect(find.text('Add account'), findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('add account route'), findsOneWidget);
  });

  testWidgets('remove asks for confirmation with the design copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AccountState(
          accounts: [
            _account('a', 'Knight', isSeedAnchor: true),
            _account('b', 'Viking'),
          ],
          activeAccountUuid: 'a',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_accounts_menu_b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove account'));
    await tester.pumpAndSettle();

    expect(find.text('Remove account'), findsOneWidget);
    expect(find.textContaining("can't be reverted"), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't be reverted"), findsNothing);
  });
}
