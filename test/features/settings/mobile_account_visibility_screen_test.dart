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
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_surface_card.dart';
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
      expect(find.text('Create an account passcode'), findsOneWidget);
      expect(find.text('Manage an account passcode'), findsOneWidget);
      expect(find.textContaining('that account is hidden'), findsOneWidget);
      expect(find.text(_private.name), findsNothing);
      await tester.tap(find.text('Manage an account passcode'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the account passcode'), findsOneWidget);
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
      await tester.tap(find.text('Manage an account passcode'));
      await tester.pumpAndSettle();
      await _enter(tester, '246810');

      expect(find.text('Now enter your wallet passcode'), findsOneWidget);
      expect(find.text(_private.name), findsNothing);
      await _enter(tester, '123456');
      expect(
        find.widgetWithText(MobileSurfaceCard, _private.name),
        findsOneWidget,
      );
      expect(find.text('Change passcode'), findsOneWidget);
      expect(find.text('Unlink'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNothing);
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

      await tester.tap(find.text('Create an account passcode'));
      await tester.pumpAndSettle();
      await _enter(tester, '123456');
      expect(find.text(_private.name), findsNothing);
      final continueButton = find.widgetWithText(AppButton, 'Continue');
      expect(tester.widget<AppButton>(continueButton).onPressed, isNull);
      await tester.tap(
        find.byKey(const ValueKey('account_visibility_choice_a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('account_visibility_choice_b')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await _enter(tester, '654321');
      await _enter(tester, '654321');

      expect(find.text('Passcode set'), findsOneWidget);
      expect(find.textContaining('see just this account'), findsOneWidget);
      expect(
        find.widgetWithText(MobileSurfaceCard, _travel.name),
        findsOneWidget,
      );
      expect(find.text(_private.name), findsNothing);
      expect(store.saved?.rule('private')?.accountIds, {_private.uuid});
      expect(
        store.saved?.rules
            .singleWhere((rule) => rule.id != 'private')
            .accountIds,
        {_travel.uuid},
      );
      expect(container.read(visibleAccountsProvider), [_everyday]);
      expect(container.read(visibleOwnAccountAddressesProvider), isEmpty);
    },
  );

  testWidgets('the last regular account stays in the regular list', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store, includeTravel: false);
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.textContaining('Keep at least one account'), findsNothing);

    await tester.tap(find.text('Create an account passcode'));
    await tester.pumpAndSettle();
    await _enter(tester, '123456');

    expect(find.textContaining('Keep at least one account'), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNothing);
    final button = find.widgetWithText(AppButton, 'Continue');
    expect(tester.widget<AppButton>(button).onPressed, isNull);
    await expectLater(
      container
          .read(mobileAccountVisibilityProvider.notifier)
          .change(
            isCurrent: () => true,
            ruleId: null,
            accountId: _everyday.uuid,
            newPasscode: '654321',
          ),
      throwsA(
        isA<MobileAccountVisibilityEditException>().having(
          (error) => error.failure,
          'failure',
          MobileAccountVisibilityEditFailure.keepOrdinary,
        ),
      ),
    );
    expect(store.saved, isNull);
  });

  testWidgets('changing a passcode keeps the linked account', (tester) async {
    final store = _Store();
    final container = _container(store);
    addTearDown(container.dispose);
    await _pump(tester, container);
    await tester.tap(find.text('Manage an account passcode'));
    await tester.pumpAndSettle();
    await _enter(tester, '246810');
    await _enter(tester, '123456');

    await tester.tap(find.text('Change passcode'));
    await tester.pumpAndSettle();
    await _enter(tester, '246810');
    expect(find.text('Confirm the account passcode'), findsOneWidget);
    await _enter(tester, '246810');
    expect(find.text('Choose a different passcode.'), findsOneWidget);
    expect(store.saved, isNull);

    await _enter(tester, '654321');
    await _enter(tester, '654321');
    expect(
      find.widgetWithText(MobileSurfaceCard, _private.name),
      findsOneWidget,
    );
    expect(store.saved?.rule('private')?.accountIds, {_private.uuid});
    expect(store.saved?.rule('private')?.verifier, '$_salt/654321');
  });

  testWidgets('a legacy shared passcode remains readable and can be unlinked', (
    tester,
  ) async {
    final store = _Store();
    final container = _container(store, legacy: true);
    addTearDown(container.dispose);
    await _pump(tester, container);
    final loaded = container.read(mobileAccountVisibilityProvider);
    final decoded = MobileAccountVisibilityConfig.decode(loaded.encode());
    expect(decoded.rule('private')?.accountIds, {_private.uuid, _travel.uuid});
    expect(container.read(visibleAccountsProvider), [_everyday]);
    expect(find.textContaining('linked to multiple accounts'), findsNothing);

    await tester.tap(find.text('Manage an account passcode'));
    await tester.pumpAndSettle();
    await _enter(tester, '246810');
    await _enter(tester, '123456');
    expect(
      find.widgetWithText(MobileSurfaceCard, _travel.name),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(MobileSurfaceCard, _private.name),
      findsOneWidget,
    );
    expect(find.textContaining('linked to multiple accounts'), findsOneWidget);
    expect(find.text('Change passcode'), findsNothing);
    await expectLater(
      container
          .read(mobileAccountVisibilityProvider.notifier)
          .change(
            isCurrent: () => true,
            ruleId: 'private',
            newPasscode: '654321',
          ),
      throwsA(isA<MobileAccountVisibilityEditException>()),
    );
    expect(store.saved, isNull);

    await tester.tap(find.text('Unlink'));
    await tester.pumpAndSettle();
    expect(find.textContaining('These accounts will appear'), findsOneWidget);
    final confirm = find.widgetWithText(AppButton, 'Unlink');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(store.saved?.rules, isEmpty);
    expect(container.read(visibleAccountsProvider), [
      _everyday,
      _travel,
      _private,
    ]);
    expect(find.text('Manage an account passcode'), findsOneWidget);
    expect(find.text(_private.name), findsNothing);
  });

  testWidgets('account choice title and controls fit with enlarged text', (
    tester,
  ) async {
    await loadFigmaCompareFonts();
    final container = _container(_Store());
    addTearDown(container.dispose);
    await _pump(tester, container);
    await tester.tap(find.text('Create an account passcode'));
    await tester.pumpAndSettle();
    await _enter(tester, '123456');

    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    final title = find.text('Choose an account');
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );

    final account = find.byKey(const ValueKey('account_visibility_choice_b'));
    await tester.ensureVisible(account);
    await tester.pumpAndSettle();
    expect(account.hitTestable(), findsOneWidget);
    await tester.tap(account);
    await tester.pumpAndSettle();
    final next = find.widgetWithText(AppButton, 'Continue');
    expect(next.hitTestable(), findsOneWidget);
    expect(tester.widget<AppButton>(next).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
