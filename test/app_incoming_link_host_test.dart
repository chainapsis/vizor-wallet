import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/send/services/payment_request_precheck.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/payment_request_flow_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';

// Both link products arrive on one native channel and are now dispatched by
// one host. Two things have to hold at once:
//
//  1. each kind still reaches its own intake — the merge did not silently
//     leave one of them handled by the other's parser;
//  2. they defer to each other. A Gift Card navigates to `/payment-links`,
//     which would tear a ZIP-321 request card off the screen mid-answer, so
//     it waits for the card and opens when the card is gone.
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

  Future<(ProviderContainer, GoRouter, _FakeIncomingUriService)> pumpHost(
    WidgetTester tester, {
    bool registerPaymentLinks = true,
  }) async {
    final incomingUris = _FakeIncomingUriService();
    addTearDown(incomingUris.dispose);

    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in [
          '/home',
          '/send',
          '/welcome',
          '/unlock',
          if (registerPaymentLinks) '/payment-links',
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
          accountProvider.overrideWith(
            () => _ControllableAccountNotifier(walletState),
          ),
          syncProvider.overrideWith(FakeSyncNotifier.new),
          paymentRequestPrecheckProvider.overrideWithValue(_readyPrecheck()),
          incomingUriServiceProvider.overrideWithValue(incomingUris),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
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
    return (container, router, incomingUris);
  }

  testWidgets('one host routes each link kind to its own intake', (
    tester,
  ) async {
    final (container, router, incomingUris) = await pumpHost(tester);

    incomingUris.emit('zcash:u1recipient?amount=0.5');
    await tester.pumpAndSettle();

    expect(
      container.read(paymentRequestFlowProvider),
      isNotNull,
      reason: 'the zcash: link became a request card',
    );
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink,
      isNull,
      reason: 'and it did not leak into the Gift Card queue',
    );
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');

    // Answer the card so the Gift Card is not deferred by it.
    container.read(paymentRequestFlowProvider.notifier).clear();
    await tester.pumpAndSettle();

    incomingUris.emit(_paymentLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(
      container.read(paymentLinkIntakeProvider).pendingLink,
      isNotNull,
      reason: 'the https link became a queued Gift Card',
    );
    expect(
      container.read(paymentUriPrefillProvider),
      isNull,
      reason: 'and it never reached the ZIP-321 park',
    );
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/payment-links',
    );
  });

  testWidgets('a Gift Card waits for a presented request card and opens once '
      'it is answered', (tester) async {
    final (container, router, incomingUris) = await pumpHost(tester);

    incomingUris.emit('zcash:u1recipient?amount=0.5');
    await tester.pumpAndSettle();
    expect(container.read(paymentRequestFlowProvider), isNotNull);

    incomingUris.emit(_paymentLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/home',
      reason: 'navigating now would unmount the card the user is answering',
    );
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink,
      isNotNull,
      reason: 'the Gift Card waits, it is not dropped',
    );
    expect(find.text(kPaymentLinkDeferredByActiveFlowMessage), findsOneWidget);

    // The user answers the card. The Gift Card is released by the same
    // listener that watches the card's own state.
    container.read(paymentRequestFlowProvider.notifier).clear();
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/payment-links',
    );
  });

  testWidgets('a Gift Card stays pending while its surface is not registered', (
    tester,
  ) async {
    final (container, router, incomingUris) = await pumpHost(
      tester,
      registerPaymentLinks: false,
    );

    incomingUris.emit(_paymentLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);
  });

  testWidgets('an unknown link on the Vizor host is dropped without a word', (
    tester,
  ) async {
    final (container, router, incomingUris) = await pumpHost(tester);

    incomingUris.emit('https://link.vizor.cash/not-a-route#v1=secret');
    await tester.pumpAndSettle();

    expect(container.read(paymentRequestFlowProvider), isNull);
    expect(container.read(paymentUriPrefillProvider), isNull);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    // No ZIP-321 rejection sentence: the link never reached that parser.
    expect(find.textContaining('payment link'), findsNothing);
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

final _paymentLink = VizorPaymentLink(
  network: 'main',
  address: 'u1giftcardaddress',
  amountZatoshi: BigInt.from(100000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Gift Card',
  createdAt: DateTime.utc(2026, 8, 28),
);

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
