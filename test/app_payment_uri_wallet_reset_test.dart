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
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/payment_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';

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
    source: kPaymentUriPrefillSource,
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
            paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
            syncProvider.overrideWith(FakeSyncNotifier.new),
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

      // A link arrives and parks: locked, so nothing is presented yet.
      container.read(paymentUriPrefillProvider.notifier).set(parkedPrefill);
      await tester.pumpAndSettle();
      expect(container.read(paymentUriPrefillProvider), parkedPrefill);

      // And a card left over from before the lock is torn down by the same
      // reset — a request cannot outlive the wallet it was going to pay from.
      container
          .read(paymentRequestFlowProvider.notifier)
          .present(parkedPrefill, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();
      expect(container.read(paymentRequestFlowProvider), isNotNull);

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
        container.read(paymentRequestFlowProvider),
        isNull,
        reason: 'the card must be dropped by the reset too',
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
            paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
            syncProvider.overrideWith(FakeSyncNotifier.new),
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

  // The delivered link no longer navigates to /send. It becomes a card over
  // whatever the user was already looking at.
  testWidgets('a delivered link presents the card without navigating', (
    tester,
  ) async {
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
            _unlockedBootstrapWithWallet(walletState),
          ),
          accountProvider.overrideWith(() => accounts),
          paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
          syncProvider.overrideWith(FakeSyncNotifier.new),
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

    await PaymentUriService.initialize();
    await _pushNativeUris(tester, const ['zcash:u1parked?amount=0.5']);
    await tester.pumpAndSettle();

    expect(
      container.read(paymentUriPrefillProvider),
      isNull,
      reason: 'the park is handed to the card',
    );
    expect(container.read(paymentRequestFlowProvider), isNotNull);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/home',
      reason: 'the card arrives over the current screen, it is not a route',
    );
  });

  // A link that arrives while a broadcast is still running waits for the
  // receipt. The card's Review and Edit both `go(...)`, which unmounts
  // `/send/status`; `runSendBroadcast`'s `shouldAbort: () async => !mounted`
  // then discards the outcome at its post-`executeProposal` checkpoint, so the
  // transaction is on the network with no txid and no receipt for the user.
  testWidgets('a link arriving mid-broadcast waits for the receipt', (
    tester,
  ) async {
    final accounts = _ControllableAccountNotifier(walletState);
    final router = GoRouter(
      initialLocation: '/send/status',
      routes: [
        for (final path in [
          '/home',
          '/send',
          '/send/status',
          '/welcome',
          '/unlock',
        ])
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
            _unlockedBootstrapWithWallet(walletState),
          ),
          accountProvider.overrideWith(() => accounts),
          paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
          syncProvider.overrideWith(FakeSyncNotifier.new),
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

    // `sendStatusTerminalProvider` starts false, which is what a broadcast in
    // progress reads as.
    expect(container.read(sendStatusTerminalProvider), isFalse);

    await PaymentUriService.initialize();
    await _pushNativeUris(tester, const ['zcash:u1parked?amount=0.5']);
    await tester.pumpAndSettle();

    expect(
      container.read(paymentRequestFlowProvider),
      isNull,
      reason: 'no card over a send that has not finished broadcasting',
    );
    expect(
      container.read(paymentUriPrefillProvider),
      isNotNull,
      reason: 'the link waits rather than being dropped',
    );

    // The send reaches a terminal phase. The listener on the flag re-drains.
    container.read(sendStatusTerminalProvider.notifier).markTerminal();
    await tester.pumpAndSettle();

    expect(container.read(paymentRequestFlowProvider), isNotNull);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/send/status',
      reason: 'the card arrives over the receipt, it does not navigate',
    );
  });
}

/// A pre-check that always resolves "ready", so the delivery test can assert
/// the card's arrival without a Rust bridge.
PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  spendableIsAuthoritativeNow: () => true,
  validateAddress: ({required String address, required String network}) async =>
      rust_sync.AddressValidationResult(
        isValid: true,
        addressType: 'unified',
        wrongNetwork: false,
      ),
  proposeTransfer:
      ({
        required String accountUuid,
        required String sendFlowId,
        required String address,
        required String addressType,
        required BigInt amountZatoshi,
        String? memo,
        bool isPaymentRequest = false,
        String? requestedBy,
        BigInt? requestedAmountZatoshi,
      }) async => SendReviewArgs(
        proposalId: BigInt.one,
        sendFlowId: sendFlowId,
        proposalAccountUuid: accountUuid,
        address: address,
        addressType: addressType,
        amountZatoshi: amountZatoshi,
        feeZatoshi: BigInt.from(10000),
        needsSaplingParams: false,
        isPaymentRequest: isPaymentRequest,
      ),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async {},
);

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
