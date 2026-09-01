import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_drain_policy.dart';
import 'package:zcash_wallet/src/features/send/models/send_prefill_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/services/payment_uri_service.dart';

// A `zcash:` link parked while the wallet is locked must disappear quietly
// when the user resets the wallet from the locked screens — no "Set up or
// import a wallet" snackbar, no jump to /welcome.
//
// The regression this pins is the *cold locked start*: `AccountNotifier.build`
// returns the bootstrap snapshot synchronously, so `ref.listen(walletProvider)`
// in the listener never fires before the reset. Unless the listener seeds its
// wallet-existence baseline up front, the reset emission is the first value it
// ever sees and it cannot tell a reset from a fresh install.
void main() {
  const parkedPrefill = SendPrefillArgs(
    id: 'payment-uri-1',
    source: 'zcash-uri',
    address: 'u1parked',
    amountText: '0.5',
  );

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

  testWidgets(
    'a wallet reset from a cold locked start drops the parked link quietly',
    (tester) async {
      final accounts = _ControllableAccountNotifier(walletState);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          for (final path in ['/home', '/send', '/welcome', '/unlock'])
            GoRoute(
              path: path,
              builder: (_, _) => Scaffold(body: Text('screen $path')),
            ),
        ],
      );
      addTearDown(router.dispose);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Locked, but a wallet exists: the shape of every mobile
            // forgot-passcode reset and of a desktop /lost-password reset.
            appBootstrapProvider.overrideWithValue(
              _lockedBootstrapWithWallet(walletState),
            ),
            accountProvider.overrideWith(() => accounts),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context, listen: false);
              return MaterialApp.router(
                routerConfig: router,
                builder: (context, child) => buildPaymentUriLinkListenerForTest(
                  router: router,
                  child: child!,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A link arrives and parks: locked, so nothing is delivered yet.
      container.read(paymentUriPrefillProvider.notifier).set(parkedPrefill);
      await tester.pumpAndSettle();
      expect(container.read(paymentUriPrefillProvider), parkedPrefill);

      // The user resets the wallet. `resetWallet` ends with an empty
      // AccountState, which is the only wallet emission this session has had.
      accounts.emit(const AccountState());
      await tester.pumpAndSettle();

      expect(
        container.read(paymentUriPrefillProvider),
        isNull,
        reason: 'the parked link must be dropped by the reset',
      );
      expect(
        find.text(kPaymentUriNoWalletMessage),
        findsNothing,
        reason: 'the wipe must not be followed by a no-wallet snackbar',
      );
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/home',
        reason: 'the reset must not be redirected to /welcome by the link',
      );
    },
  );

  // Two `zcash:` links delivered back-to-back while the wallet is locked: the
  // first parks for the unlock screen, the second displaces it. The prefill
  // holds one link at a time on purpose (latest wins, no queue), so the user
  // has to be told the earlier link is gone instead of silently getting the
  // wrong payment on the next unlock.
  testWidgets(
    'a second link arriving while the first is parked says so and keeps the '
    'newer one',
    (tester) async {
      const firstUri = 'zcash:u1firstlink?amount=0.5';
      const secondUri = 'zcash:u1secondlink?amount=0.25';

      final accounts = _ControllableAccountNotifier(walletState);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          for (final path in ['/home', '/send', '/welcome', '/unlock'])
            GoRoute(
              path: path,
              builder: (_, _) => Scaffold(body: Text('screen $path')),
            ),
        ],
      );
      addTearDown(router.dispose);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _lockedBootstrapWithWallet(walletState),
            ),
            accountProvider.overrideWith(() => accounts),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context, listen: false);
              return MaterialApp.router(
                routerConfig: router,
                builder: (context, child) => buildPaymentUriLinkListenerForTest(
                  router: router,
                  child: child!,
                ),
              );
            },
          ),
        ),
      );
      // The listener installs the PaymentUriService method-call handler in
      // initState; initialize() is idempotent and only awaited here so the
      // handler is guaranteed to be in place before the native push below.
      await PaymentUriService.initialize();
      await tester.pumpAndSettle();

      // The native side flushes both links in one batch — the cold-start
      // shape, and the same code path as two separate pushes.
      await _pushNativeUris(tester, const [firstUri, secondUri]);
      await tester.pumpAndSettle();

      final parked = container.read(paymentUriPrefillProvider);
      expect(
        parked?.address,
        'u1secondlink',
        reason: 'latest wins: the second link must be the parked one',
      );
      expect(
        find.text(kPaymentUriReplacedMessage),
        findsOneWidget,
        reason: 'the dropped first link must be visible to the user',
      );
      // Locked with a wallet: the drain parks and routes to the unlock screen,
      // which claims the prefill after a successful unlock.
      expect(router.routerDelegate.currentConfiguration.uri.path, '/unlock');
    },
  );
}

/// Delivers [uris] the way the native runner does: an `onUris` method call on
/// the payment-URI channel, which PaymentUriService forwards to its stream.
Future<void> _pushNativeUris(WidgetTester tester, List<String> uris) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'com.zcash.wallet/payment_uri',
    codec.encodeMethodCall(MethodCall('onUris', uris)),
    (_) {},
  );
}

AppBootstrapState _lockedBootstrapWithWallet(AccountState accountState) =>
    AppBootstrapState(
      initialLocation: '/unlock',
      initialAccountState: accountState,
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.dark,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: false,
      passwordRotationRecoveryFailed: false,
    );

class _ControllableAccountNotifier extends AccountNotifier {
  _ControllableAccountNotifier(this._initial);

  final AccountState _initial;

  @override
  FutureOr<AccountState> build() => _initial;

  void emit(AccountState next) => state = AsyncData(next);
}
