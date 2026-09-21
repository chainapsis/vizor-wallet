import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';

// A bare-origin Vizor link means no more than "open Vizor", and Vizor is
// already open by the time the host sees one. It therefore loses to anything
// the user is part-way through: onboarding, import, and add-account hold a
// typed seed phrase or a freshly generated mnemonic in the widget tree alone,
// and `go('/home')` would throw that away with no way back.
//
// The harness mirrors `app_incoming_link_host_test.dart`: a fake
// `IncomingUriService` rather than the real platform channel, and the same
// unlocked-wallet bootstrap. `_IncomingLinkHost` grows more provider reads as
// the link stack lands on top of this PR, and every one of them resolves from
// this bootstrap, so the file keeps passing as the host gains lanes.
void main() {
  const homeLink = 'https://link.vizor.cash';

  const account = AccountInfo(
    uuid: 'account-1',
    name: 'Account 1',
    order: 0,
    isSeedAnchor: true,
  );

  const walletState = AccountState(
    accounts: [account],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1active',
  );

  Future<(GoRouter, _FakeIncomingUriService)> pumpHost(
    WidgetTester tester, {
    required String initialLocation,
  }) async {
    final incomingUris = _FakeIncomingUriService();
    addTearDown(incomingUris.dispose);

    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        for (final path in const [
          '/home',
          '/activity',
          '/settings',
          '/welcome',
          '/add-account',
          '/onboarding/secret-passphrase',
          '/import/secret-passphrase',
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('screen $path')),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _unlockedBootstrapWithWallet(walletState),
          ),
          accountProvider.overrideWith(
            () => _ControllableAccountNotifier(walletState),
          ),
          syncProvider.overrideWith(FakeSyncNotifier.new),
          incomingUriServiceProvider.overrideWithValue(incomingUris),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppTheme(
            data: AppThemeData.dark,
            child: buildIncomingLinkHostForTest(router: router, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (router, incomingUris);
  }

  String locationOf(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  for (final origin in const [
    '/welcome',
    '/add-account',
    '/onboarding/secret-passphrase',
    '/import/secret-passphrase',
  ]) {
    testWidgets('a home link on $origin does not navigate', (tester) async {
      final (router, incomingUris) = await pumpHost(
        tester,
        initialLocation: origin,
      );
      expect(locationOf(router), origin);

      incomingUris.emit(homeLink);
      await tester.pumpAndSettle();

      expect(
        locationOf(router),
        origin,
        reason: 'the in-progress screen must survive a bare-origin link',
      );
    });
  }

  for (final origin in const ['/activity', '/settings']) {
    testWidgets('a home link on $origin goes home', (tester) async {
      final (router, incomingUris) = await pumpHost(
        tester,
        initialLocation: origin,
      );
      expect(locationOf(router), origin);

      incomingUris.emit(homeLink);
      await tester.pumpAndSettle();

      expect(locationOf(router), '/home');
    });
  }

  testWidgets('a home link goes home once onboarding is left behind', (
    tester,
  ) async {
    // The gate is on where the user is now, not on where the app started: the
    // same link that was dropped during onboarding must work afterwards.
    final (router, incomingUris) = await pumpHost(
      tester,
      initialLocation: '/onboarding/secret-passphrase',
    );

    incomingUris.emit(homeLink);
    await tester.pumpAndSettle();
    expect(locationOf(router), '/onboarding/secret-passphrase');

    router.go('/activity');
    await tester.pumpAndSettle();

    incomingUris.emit(homeLink);
    await tester.pumpAndSettle();
    expect(locationOf(router), '/home');
  });
}

class _FakeIncomingUriService extends IncomingUriService {
  final StreamController<String> _uris = StreamController<String>.broadcast();

  @override
  Stream<String> get uriStream => _uris.stream;

  @override
  Future<void> initialize() async {}

  void emit(String uri) => _uris.add(uri);

  @override
  Future<void> dispose() async {
    await _uris.close();
  }
}

AppBootstrapState _unlockedBootstrapWithWallet(AccountState accountState) =>
    AppBootstrapState(
      initialLocation: '/home',
      initialAccountState: accountState,
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.dark,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
    );

class _ControllableAccountNotifier extends AccountNotifier {
  _ControllableAccountNotifier(this._initial);

  final AccountState _initial;

  @override
  FutureOr<AccountState> build() => _initial;
}
