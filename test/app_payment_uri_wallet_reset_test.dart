import 'dart:async';

import 'package:flutter/material.dart';
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
