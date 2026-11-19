@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/accounts/screens/mobile/mobile_accounts_screen.dart';
import 'package:zcash_wallet/src/features/send/widgets/send_recipient_resolver.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_account_visibility_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/mobile_account_visibility_provider.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

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

ProviderContainer _container(
  _Store store, {
  bool configured = true,
  bool includeTravel = true,
  bool legacy = false,
}) {
  final configuration = configured
      ? MobileAccountVisibilityConfig(
          salt: _salt,
          rules: [
            MobileAccountVisibilityRule(
              id: 'private',
              verifier: '$_salt/246810',
              accountIds: {_private.uuid, if (legacy) _travel.uuid},
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
            accounts: [
              _everyday,
              if (includeTravel) _travel,
              if (configured) _private,
            ],
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

Future<GoRouter> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  String location = '/accounts',
  MobileAccountPasscodeEntry? entry,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    initialLocation: location,
    initialExtra: entry,
    routes: [
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const MobileAccountsScreen(),
      ),
      GoRoute(
        path: mobileAccountPasscodePath,
        builder: (_, state) => MobileAccountVisibilityScreen(
          entry: state.extra as MobileAccountPasscodeEntry,
        ),
      ),
      GoRoute(
        path: '/settings/account-visibility',
        builder: (_, _) => const MobileAccountVisibilityGuideScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: appLocalizationsDelegates,
        builder: (_, child) =>
            AppTheme(data: AppThemeData.light, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _chooseAction(
  WidgetTester tester,
  String account,
  String action,
) async {
  await tester.tap(find.byKey(ValueKey('mobile_accounts_menu_$account')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('mobile_account_menu_${action}_passcode')),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLinkedView(ProviderContainer container) async {
  await container.read(accountProvider.future);
  container.read(mobileAccountScopeProvider.notifier).select('private');
  container
      .read(accountProvider.notifier)
      .selectMobileAccountBeforeUnlock('private');
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
    testWidgets(
      'Settings and regular account menus are neutral with configured=$configured',
      (tester) async {
        final container = _container(_Store(), configured: configured);
        addTearDown(container.dispose);
        final router = await _pump(
          tester,
          container,
          location: '/settings/account-visibility',
        );
        expect(find.text('Accounts by passcode'), findsOneWidget);
        expect(
          find.textContaining('tap ⋯ next to the account'),
          findsOneWidget,
        );
        expect(find.text('Create a dedicated passcode'), findsNothing);
        expect(find.text('Stop viewing separately'), findsNothing);
        expect(find.text(_private.name), findsNothing);

        router.go('/accounts');
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('mobile_accounts_menu_${_travel.uuid}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('View this account separately'), findsOneWidget);
        expect(find.text('Change dedicated passcode'), findsNothing);
        expect(find.text('Stop viewing separately'), findsNothing);
        expect(find.text(_private.name), findsNothing);
      },
    );
  }

  testWidgets('the account menu creates a code for the selected account', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store);
    addTearDown(container.dispose);
    await container.read(ownAccountAddressesProvider.future);
    final router = await _pump(tester, container);

    await _chooseAction(tester, _travel.uuid, 'create');
    expect(router.state.uri.path, mobileAccountPasscodePath);
    expect(find.textContaining('Travel is hidden'), findsOneWidget);
    expect(find.textContaining('only Travel appears'), findsOneWidget);
    await tester.tap(find.text('Create a dedicated passcode'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your wallet passcode'), findsOneWidget);
    await _enter(tester, '999999');
    expect(find.text('Incorrect Passcode'), findsOneWidget);
    expect(store.saved, isNull);

    await _enter(tester, '123456');
    expect(find.text('Choose a dedicated passcode'), findsOneWidget);
    await _enter(tester, '654321');
    expect(find.text('Confirm the dedicated passcode'), findsOneWidget);
    await _enter(tester, '654321');
    expect(find.text('Passcode set'), findsOneWidget);
    expect(find.textContaining('on the lock screen'), findsOneWidget);
    expect(store.saved?.rule('private')?.accountIds, {_private.uuid});
    expect(
      store.saved?.rules.singleWhere((rule) => rule.id != 'private').accountIds,
      {_travel.uuid},
    );
    expect(container.read(visibleAccountsProvider), [_everyday]);
    expect(container.read(visibleOwnAccountAddressesProvider), isEmpty);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/accounts');
  });

  testWidgets('the last regular account stays in the regular list', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store, includeTravel: false);
    addTearDown(container.dispose);
    await _pump(tester, container);
    await tester.tap(
      find.byKey(ValueKey('mobile_accounts_menu_${_everyday.uuid}')),
    );
    await tester.pumpAndSettle();
    final setup = find.text('View this account separately');
    expect(
      tester.getTopLeft(find.text('Reset Vizor')).dy,
      greaterThan(tester.getBottomLeft(setup).dy),
    );
    await tester.tap(setup);
    await tester.pumpAndSettle();
    expect(find.textContaining('Keep at least one account'), findsNothing);
    await tester.tap(find.text('Create a dedicated passcode'));
    await tester.pumpAndSettle();
    await _enter(tester, '123456');
    expect(find.textContaining('Keep at least one account'), findsOneWidget);
    expect(find.text('Choose a dedicated passcode'), findsNothing);
    expect(store.saved, isNull);
  });

  testWidgets('the linked session changes a passcode for the same account', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store);
    addTearDown(container.dispose);
    await _openLinkedView(container);
    final router = await _pump(tester, container);

    await tester.tap(
      find.byKey(ValueKey('mobile_accounts_menu_${_private.uuid}')),
    );
    await tester.pumpAndSettle();
    final divider = find.byKey(
      const ValueKey('mobile_account_menu_passcode_divider'),
    );
    final change = find.text('Change dedicated passcode');
    final unlink = find.text('Stop viewing separately');
    expect(
      tester.getTopLeft(divider).dy,
      greaterThan(tester.getBottomLeft(find.text('Edit account')).dy),
    );
    expect(
      tester.getTopLeft(change).dy,
      greaterThan(tester.getBottomLeft(divider).dy),
    );
    expect(
      tester.getTopLeft(unlink).dy,
      greaterThan(tester.getBottomLeft(change).dy),
    );
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(find.text('Choose a dedicated passcode'), findsOneWidget);
    expect(find.text('Enter your wallet passcode'), findsNothing);
    await _enter(tester, '246810');
    await _enter(tester, '246810');
    expect(find.text('Choose a different passcode.'), findsOneWidget);
    expect(store.saved, isNull);
    await _enter(tester, '654321');
    await _enter(tester, '654321');

    expect(find.text('Passcode set'), findsOneWidget);
    expect(store.saved?.rule('private')?.accountIds, {_private.uuid});
    expect(store.saved?.rule('private')?.verifier, '$_salt/654321');
    expect(container.read(visibleAccountsProvider), [_private]);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/accounts');
  });

  testWidgets(
    'unlink confirms, retires the code and restores the regular list',
    (tester) async {
      final store = _Store();
      final container = _container(store);
      addTearDown(container.dispose);
      await _openLinkedView(container);
      final router = await _pump(tester, container);

      await _chooseAction(tester, _private.uuid, 'unlink');
      expect(find.text('Stop viewing separately?'), findsOneWidget);
      expect(
        find.textContaining(
          'Long term will appear in the regular account list',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.saved, isNull);
      expect(container.read(visibleAccountsProvider), [_private]);

      bool? protectedAtScopeClear;
      final subscription = container.listen(mobileAccountScopeProvider, (
        old,
        next,
      ) {
        if (old != null && next == null) {
          protectedAtScopeClear = container.read(
            mobileAccountManagementOpenProvider,
          );
        }
      });
      addTearDown(subscription.close);
      await _chooseAction(tester, _private.uuid, 'unlink');
      await tester.tap(
        find.widgetWithText(AppButton, 'Stop viewing separately'),
      );
      await tester.pumpAndSettle();
      expect(protectedAtScopeClear, isTrue);
      expect(container.read(mobileAccountManagementOpenProvider), isFalse);
      expect(store.saved?.rules, isEmpty);
      expect(container.read(mobileAccountScopeProvider), isNull);
      expect(container.read(visibleAccountsProvider), [
        _everyday,
        _travel,
        _private,
      ]);
      expect(router.state.uri.path, '/accounts');
      expect(
        container.read(accountProvider).value?.activeAccountUuid,
        _private.uuid,
      );
    },
  );

  testWidgets(
    'a regular session cannot reach private actions with a route payload',
    (tester) async {
      final store = _Store();
      final container = _container(store);
      addTearDown(container.dispose);
      final router = await _pump(tester, container);
      for (final action in [
        MobileAccountPasscodeAction.change,
        MobileAccountPasscodeAction.unlink,
      ]) {
        router.push(
          mobileAccountPasscodePath,
          extra: MobileAccountPasscodeEntry(_private.uuid, action),
        );
        await tester.pumpAndSettle();
        expect(find.text(_private.name), findsNothing);
        expect(find.text('Stop viewing separately'), findsNothing);
        expect(find.bySemanticsLabel('Digit 1'), findsNothing);
        router.pop();
        await tester.pumpAndSettle();
      }
      await expectLater(
        container
            .read(mobileAccountVisibilityProvider.notifier)
            .change(isCurrent: () => true, ruleId: 'private', remove: true),
        throwsA(isA<SecureStorageSessionChangedException>()),
      );
      expect(store.saved, isNull);
    },
  );

  testWidgets('a retained route loses unlink controls when its scope ends', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store);
    addTearDown(container.dispose);
    await _openLinkedView(container);
    await _pump(tester, container);
    await _chooseAction(tester, _private.uuid, 'unlink');
    expect(find.textContaining('Long term will appear'), findsOneWidget);

    container.read(mobileAccountScopeProvider.notifier).select(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('Long term will appear'), findsNothing);
    expect(find.text('Stop viewing separately'), findsNothing);
    expect(store.saved, isNull);
  });

  testWidgets('a legacy linked view can unlink its shared passcode', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store, legacy: true);
    addTearDown(container.dispose);
    await _openLinkedView(container);
    await _pump(tester, container);
    await tester.tap(
      find.byKey(ValueKey('mobile_accounts_menu_${_private.uuid}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Change dedicated passcode'), findsNothing);
    final divider = find.byKey(
      const ValueKey('mobile_account_menu_passcode_divider'),
    );
    final unlink = find.text('Stop viewing separately');
    expect(
      tester.getTopLeft(unlink).dy,
      greaterThan(tester.getBottomLeft(divider).dy),
    );
    expect(
      tester.getTopLeft(find.text('Remove account')).dy,
      greaterThan(tester.getBottomLeft(unlink).dy),
    );
    await tester.tap(unlink);
    await tester.pumpAndSettle();
    expect(find.textContaining('These accounts will appear'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Stop viewing separately'));
    await tester.pumpAndSettle();
    expect(store.saved?.rules, isEmpty);
    expect(container.read(visibleAccountsProvider), [
      _everyday,
      _travel,
      _private,
    ]);
  });

  testWidgets('the last account action stays readable at 200% text', (
    tester,
  ) async {
    await loadFigmaCompareFonts();
    final container = _container(_Store(), legacy: true);
    addTearDown(container.dispose);
    await _openLinkedView(container);
    await _pump(tester, container);
    tester.view.physicalSize = const Size(320, 336);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('mobile_accounts_menu_${_travel.uuid}')),
    );
    await tester.pumpAndSettle();

    final remove = find.text('Remove account');
    await tester.ensureVisible(remove);
    await tester.pumpAndSettle();
    expect(remove.hitTestable(), findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(remove).didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.getTopLeft(remove).dy,
      greaterThan(
        tester.getBottomLeft(find.text('Stop viewing separately')).dy,
      ),
    );
  });
}
