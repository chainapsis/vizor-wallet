import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_hold.dart';
import 'package:zcash_wallet/src/core/navigation/payment_uri_busy_surface_provider.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'fakes/fake_sync_notifier.dart';

// A busy surface takes its hold from a post-frame callback registered in its
// own initState. A link that arrives in the same turn as the navigation that
// mounts the surface schedules its drain *before* that initState runs, so a
// drain that is itself a plain post-frame callback runs first, reads a hold
// count of zero, and presents the card over the signing surface. The drain
// has to run after every post-frame callback of the frame instead.
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

  Future<(ProviderContainer, GoRouter)> pumpApp(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in ['/home', '/send', '/welcome', '/unlock'])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('screen $path')),
          ),
        // Stands in for every Keystone signing screen: the whole screen is
        // the protected session.
        GoRoute(
          path: '/busy',
          builder: (_, _) => const PaymentUriBusySurfaceHold(
            child: Scaffold(body: Text('screen /busy')),
          ),
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
          accountProvider.overrideWith(
            () => _ControllableAccountNotifier(walletState),
          ),
          syncProvider.overrideWith(FakeSyncNotifier.new),
          paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return MaterialApp.router(
              routerConfig: router,
              // AppTheme, because the host's notices render as app toasts.
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
    return (container, router);
  }

  testWidgets(
    'a link arriving in the frame a signing surface mounts stays parked',
    (tester) async {
      final (container, router) = await pumpApp(tester);

      // Navigation requested and the link delivered before the frame that
      // builds the signing screen — the order a QR scan that opens a signing
      // screen while a link lands produces.
      router.go('/busy');
      await _pushNativeUris(tester, const ['zcash:u1recipient?amount=1']);
      await tester.pump();

      // Built this frame; its page transition has not brought it on stage.
      expect(find.text('screen /busy', skipOffstage: false), findsOneWidget);
      expect(container.read(paymentUriBusySurfaceProvider), 1);
      expect(
        container.read(paymentRequestFlowProvider),
        isNull,
        reason: 'the card must not be presented over the signing surface',
      );
      expect(
        container.read(paymentUriPrefillProvider),
        isNotNull,
        reason: 'the link waits for the surface, it is not dropped',
      );

      // Leaving the surface gives the hold back and the parked link lands.
      router.go('/home');
      await tester.pumpAndSettle();

      expect(container.read(paymentUriBusySurfaceProvider), 0);
      expect(container.read(paymentRequestFlowProvider), isNotNull);
      expect(container.read(paymentUriPrefillProvider), isNull);
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
        proposalId: BigInt.from(11),
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
