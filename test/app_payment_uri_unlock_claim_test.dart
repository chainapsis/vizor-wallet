import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_unlock_claim.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/migration_send_gate_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'fakes/fake_sync_notifier.dart';

// `decidePaymentUriDrain` answers `wait` for a link that arrives while the
// app is on `/unlock`, whether or not the wallet is already unlocked, because
// the unlock flow owns that handoff. Nothing re-runs the drain on a route
// change — the payment lane's only re-drain triggers are a wallet emission,
// the busy count reaching zero, and the send reaching a terminal phase — so
// `claimParkedPaymentUriAfterUnlock` is not one of two ways the link can be
// delivered from there. It is the only way.
//
// That makes it worth pinning at app level: an unlock path that ever stops
// calling the claim strands the link until the park TTL, and no drain-policy
// unit test can see that.
void main() {
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
    'a link parked on /unlock is delivered by the claim, not by leaving the '
    'route',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/unlock',
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
      late WidgetRef unlockScreenRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(
              _unlockedBootstrapWithWallet(walletState),
            ),
            accountProvider.overrideWith(
              () => _ControllableAccountNotifier(walletState),
            ),
            paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
            syncProvider.overrideWith(FakeSyncNotifier.new),
            migrationSendGateProvider.overrideWithValue(false),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context, listen: false);
              // Stands in for the unlock screen's own `ref`: the claim is a
              // `WidgetRef` call the two unlock screens share.
              unlockScreenRef = ref;
              return MaterialApp.router(
                routerConfig: router,
                builder: (context, child) => AppTheme(
                  data: AppThemeData.dark,
                  child: buildIncomingLinkHostForTest(
                    router: router,
                    child: child!,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The wallet is already unlocked, but the app is still sitting on the
      // unlock route: the drain waits rather than presenting under the screen
      // that is about to navigate.
      await _pushNativeUris(tester, const ['zcash:u1parked?amount=0.5']);
      await tester.pumpAndSettle();

      expect(
        container.read(paymentUriPrefillProvider)?.address,
        'u1parked',
        reason: 'the link stays parked for the unlock flow to claim',
      );
      expect(container.read(paymentRequestFlowProvider), isNull);

      // Leaving the route is not a delivery. The payment lane has no
      // route-change re-drain, so nothing happens here — which is exactly why
      // the claim below has to be the thing that delivers.
      router.go('/home');
      await tester.pumpAndSettle();

      expect(
        container.read(paymentUriPrefillProvider)?.address,
        'u1parked',
        reason: 'a route change alone must not be mistaken for a claim',
      );
      expect(container.read(paymentRequestFlowProvider), isNull);

      // What the unlock screens actually do once the post-unlock work has
      // succeeded.
      final claim = claimParkedPaymentUriAfterUnlock(unlockScreenRef);
      expect(claim.notice, isNull);
      container
          .read(paymentRequestFlowProvider.notifier)
          .present(claim.prefill!, source: PaymentRequestSource.link);
      await tester.pumpAndSettle();

      expect(container.read(paymentUriPrefillProvider), isNull);
      expect(
        container.read(paymentRequestFlowProvider)!.prefill.address,
        'u1parked',
      );
    },
  );
}

/// Delivers [uris] the way the native runner does: an `onUris` method call on
/// the incoming-link channel, which `IncomingUriService` — installed by the
/// host under test in its `initState` — forwards to its stream.
Future<void> _pushNativeUris(WidgetTester tester, List<String> uris) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'com.zcash.wallet/payment_uri',
    codec.encodeMethodCall(MethodCall('onUris', uris)),
    (_) {},
  );
}

PaymentRequestPrecheck _readyPrecheck() => PaymentRequestPrecheck(
  readNetworkName: () => kZcashDefaultNetworkName,
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
        requestedBy: requestedBy,
        requestedAmountZatoshi: requestedAmountZatoshi,
      ),
  discardProposal:
      ({
        required BigInt proposalId,
        required String sendFlowId,
        required String logContext,
      }) async => true,
);

AppBootstrapState _unlockedBootstrapWithWallet(AccountState accountState) =>
    AppBootstrapState(
      initialLocation: '/unlock',
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
