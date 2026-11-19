@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart' show appRedirect;

import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/storage/account_visibility_store.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_account_visibility_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/mobile_account_visibility_provider.dart';

const _everyday = AccountInfo(uuid: 'a', name: 'Everyday', order: 0);
const _travel = AccountInfo(uuid: 'b', name: 'Travel', order: 1);
const _private = AccountInfo(uuid: 'c', name: 'Long term', order: 2);
const _salt = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

class _Security extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => password == '123456';
}

class _BiometricsOff extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => BiometricUnlockState.initial;
}

class _Store extends MobileAccountVisibilityStore {
  _Store() : super(AppSecureStore.instance);

  MobileAccountVisibilityConfig? saved;

  @override
  Future<String> verifier(String code, String salt) async => '$salt/$code';

  @override
  Future<void> write(MobileAccountVisibilityConfig configuration) async {
    saved = configuration;
  }
}

ProviderContainer _container(_Store store, {bool configured = true}) {
  final configuration = configured
      ? MobileAccountVisibilityConfig(
          salt: _salt,
          rules: [
            MobileAccountVisibilityRule(
              id: 'private',
              verifier: '$_salt/246810',
              accountIds: {_private.uuid},
            ),
          ],
        )
      : const MobileAccountVisibilityConfig();
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          initialLocation: '/settings/account-visibility',
          initialAccountState: AccountState(
            accounts: [_everyday, _travel, if (configured) _private],
            activeAccountUuid: _everyday.uuid,
          ),
          initialSyncSnapshot: AppSyncSnapshot.empty,
          network: 'main',
          rpcEndpointConfig: defaultRpcEndpointConfig('main'),
          themeMode: ThemeMode.light,
          privacyModeEnabled: false,
          isPasswordConfigured: true,
          isUnlocked: true,
          passwordRotationRecoveryFailed: false,
          mobileAccountVisibility: configuration,
        ),
      ),
      appSecurityProvider.overrideWith(_Security.new),
      biometricUnlockProvider.overrideWith(_BiometricsOff.new),
      mobileAccountVisibilityStoreProvider.overrideWithValue(store),
      ownAccountAddressesProvider.overrideWith(
        (ref) async => {'u1travel': _travel, 'u1longterm': _private},
      ),
    ],
  );
}

final _redirect = Provider.autoDispose.family<String?, GoRouterState>((
  ref,
  state,
) {
  return appRedirect(
    ref: ref,
    bootstrap: ref.read(appBootstrapProvider),
    state: state,
  );
});

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
        home: const MobileAccountVisibilityScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final path in ['/gift', '/gift/scan']) {
    testWidgets('private sessions cannot add an account through $path', (
      tester,
    ) async {
      final container = _container(_Store());
      addTearDown(container.dispose);
      container.read(mobileAccountScopeProvider.notifier).select('private');
      final router = GoRouter(
        initialLocation: '$path?addAccount=true',
        redirect: (_, state) => container.read(_redirect(state)),
        routes: [
          for (final path in ['/home', '/gift', '/gift/scan', '/payment-links'])
            GoRoute(path: path, builder: (_, _) => Text(path)),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/payment-links');

      container.read(mobileAccountScopeProvider.notifier).select(null);
      router.go('$path?addAccount=true');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, path);
    });
  }

  for (final configured in [false, true]) {
    testWidgets('management entry looks the same with configured=$configured', (
      tester,
    ) async {
      final container = _container(_Store(), configured: configured);
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.text('Accounts by passcode'), findsOneWidget);
      expect(find.text('Create separate passcode'), findsOneWidget);
      expect(find.text('Manage with separate passcode'), findsOneWidget);
      expect(find.text(_private.name), findsNothing);
      await tester.tap(find.text('Manage with separate passcode'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your separate passcode.'), findsOneWidget);
      await _enter(tester, '999999');
      expect(find.text('Incorrect Passcode'), findsOneWidget);
      expect(find.text(_private.name), findsNothing);
    });
  }

  testWidgets(
    'existing linked accounts appear only after completing authentication',
    (tester) async {
      final container = _container(_Store());
      addTearDown(container.dispose);
      await _pump(tester, container);
      await tester.tap(find.text('Manage with separate passcode'));
      await tester.pumpAndSettle();
      await _enter(tester, '246810');

      expect(find.text('Enter your wallet passcode.'), findsOneWidget);
      expect(find.text(_private.name), findsNothing);
      await _enter(tester, '123456');
      expect(find.text(_private.name), findsOneWidget);
      expect(container.read(visibleAccountsProvider), [_everyday, _travel]);
    },
  );

  testWidgets(
    'adding a passcode preserves other rules and removes a cached recipient label',
    (tester) async {
      final store = _Store();
      final container = _container(store);
      addTearDown(container.dispose);
      await container.read(ownAccountAddressesProvider.future);
      expect(container.read(visibleOwnAccountAddressesProvider), {
        'u1travel': _travel,
      });
      await _pump(tester, container);

      await tester.tap(find.text('Create separate passcode'));
      await tester.pumpAndSettle();
      await _enter(tester, '123456');
      expect(find.text(_private.name), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('account_visibility_choice_b')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await _enter(tester, '654321');
      await _enter(tester, '654321');

      expect(find.text(_travel.name), findsOneWidget);
      expect(find.text(_private.name), findsNothing);
      expect(store.saved?.rule('private')?.accountIds, {_private.uuid});
      expect(store.saved?.rules, hasLength(2));
      expect(container.read(visibleAccountsProvider), [_everyday]);
      expect(container.read(visibleOwnAccountAddressesProvider), isEmpty);
    },
  );
}
