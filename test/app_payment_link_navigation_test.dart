import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_entry_price_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_flow_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/payment_links_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/gift_claim_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';
import 'support/payment_link_navigation_support.dart';
import 'support/payment_links_screen_support.dart'
    show loadPaymentLinksTestFonts;

void main() {
  test('blocks incoming Gift Cards on transactional and setup routes', () {
    for (final location in [
      '/send',
      '/send/review',
      '/swap',
      '/pay/review',
      '/add-account',
      '/onboarding/customise-account',
      '/import/birthday',
      '/migration/private/status',
      '/voting/poll/round-1/review',
      '/settings/change-password',
      '/setup/backup',
      '/setup/backup/reveal',
      '/setup/education/intro',
      '/setup/education/address-types',
    ]) {
      expect(
        paymentLinkEntryBlockedAtLocation(location),
        isTrue,
        reason: location,
      );
    }
  });

  test('defers an incoming Gift Card while a payment-request card is up', () {
    // The card owns no route, so no location test can see it. Opening the
    // Payment Links screen underneath would unmount a request the user is
    // part-way through answering.
    expect(
      paymentLinkEntryBlockedAtLocation(
        '/home',
        paymentRequestCardPresented: true,
      ),
      isTrue,
    );
    expect(
      paymentLinkEntryDeferredMessageAtLocation(
        '/home',
        paymentRequestCardPresented: true,
      ),
      kPaymentLinkDeferredByActiveFlowMessage,
    );
    // Setup still wins: its message is the more specific one.
    expect(
      paymentLinkEntryDeferredMessageAtLocation(
        '/welcome',
        paymentRequestCardPresented: true,
      ),
      kPaymentLinkDeferredByAccountSetupMessage,
    );
  });

  test('allows incoming Gift Cards on neutral routes', () {
    for (final location in [
      '/home',
      '/activity',
      '/accounts',
      '/settings',
      '/receive',
      '/setup/backup-other',
    ]) {
      expect(
        paymentLinkEntryBlockedAtLocation(location),
        isFalse,
        reason: location,
      );
    }
  });

  testWidgets('scheduled Gift navigation yields to the Payment Links scanner', (
    tester,
  ) async {
    final incomingUris = _FakeIncomingUriService();
    addTearDown(incomingUris.dispose);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        for (final path in [
          '/settings',
          '/payment-links',
          '/payment-links/scan',
          '/payment-links-other',
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
          appBootstrapProvider.overrideWithValue(readyPaymentLinkBootstrap),
          incomingUriServiceProvider.overrideWithValue(incomingUris),
          syncProvider.overrideWith(FakeSyncNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              buildIncomingLinkHostForTest(router: router, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('screen /settings')),
    );
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    // Enter the scanner after the host schedules navigation, before its
    // post-frame callback runs. The callback must re-check route ownership.
    router.go('/payment-links/scan');
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, '/payment-links/scan');
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    // A similar prefix is still a neutral route, so leaving the owned flow
    // resumes the queued link's normal navigation.
    router.go('/payment-links-other');
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, '/payment-links');
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an error for a rejected Gift Card deep link', (
    tester,
  ) async {
    final incomingUris = _FakeIncomingUriService();
    addTearDown(incomingUris.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(readyPaymentLinkBootstrap),
          incomingUriServiceProvider.overrideWithValue(incomingUris),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              SyncState(
                accountUuid: 'account-1',
                hasAccountScopedData: true,
                isSyncComplete: true,
                percentage: 1,
                displayTargetPercentage: 1,
                spendableBalance: BigInt.from(1000000),
                displaySpendableBalance: BigInt.from(1000000),
              ),
            ),
          ),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await pumpUntilPresent(tester, find.byType(SendScreen));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SendScreen)),
    );

    incomingUris.emit('https://link.vizor.cash/payment-links/open#malformed');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(container.read(paymentLinkIntakeProvider).errorMessage, isNull);
    expect(find.text('Payment link could not be opened.'), findsOneWidget);
  });

  testWidgets('opens Gift onboarding immediately from a walletless Welcome', (
    tester,
  ) async {
    final accountNotifier = _OnboardingAccountNotifier();
    final operations = _WalletlessGiftOperations();
    await loadPaymentLinksTestFonts();
    await (FontLoader(
      'YoungSerif',
    )..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'))).load();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_emptyBootstrap),
          accountProvider.overrideWith(() => accountNotifier),
          syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
          paymentLinkOperationsProvider.overrideWithValue(operations),
          giftCardEntryPriceProvider.overrideWith((_) async => null),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await pumpUntilPresent(tester, find.byType(WelcomeScreen));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await pumpUntilPresent(tester, find.byType(GiftClaimScreen));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.byType(GiftClaimScreen), findsOneWidget);
    expect(
      GoRouterState.of(tester.element(find.byType(GiftClaimScreen))).uri.path,
      '/gift',
    );
    expect(find.text(kPaymentLinkDeferredByAccountSetupMessage), findsNothing);
    // Intake retains the Card until setup owns its durable handoff.
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);
    expect(
      container.read(giftClaimFlowProvider)?.phase,
      GiftClaimPhase.checking,
    );
    expect(operations.inspectionCalls, 1);
    expect(container.read(accountProvider).value?.hasAccounts, isFalse);

    operations.finishInspection();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      container.read(giftClaimFlowProvider)?.phase,
      GiftClaimPhase.inspected,
    );
    expect(find.byType(GiftClaimScreen), findsOneWidget);
    expect(container.read(accountProvider).value?.hasAccounts, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('defers a Gift Card until the active send flow is left', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(readyPaymentLinkBootstrap),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              SyncState(
                accountUuid: 'account-1',
                hasAccountScopedData: true,
                isSyncComplete: true,
                percentage: 1,
                displayTargetPercentage: 1,
                spendableBalance: BigInt.from(1000000),
                displaySpendableBalance: BigInt.from(1000000),
              ),
            ),
          ),
          paymentLinkOperationsProvider.overrideWithValue(
            PendingClaimPaymentLinkOperations(),
          ),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await pumpUntilPresent(tester, find.byType(SendScreen));
    final sendContext = tester.element(find.byType(SendScreen));
    final container = ProviderScope.containerOf(sendContext);

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SendScreen), findsOneWidget);
    expect(find.text(kPaymentLinkDeferredByActiveFlowMessage), findsOneWidget);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    GoRouter.of(sendContext).go('/home');
    await pumpUntilPresent(tester, find.byType(PaymentLinksScreen));

    expect(find.byType(PaymentLinksScreen), findsOneWidget);
  });
}

class _OnboardingAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState();
}

class _WalletlessGiftOperations extends PendingClaimPaymentLinkOperations {
  final _inspection = Completer<PaymentLinkClaimInspection>();
  int inspectionCalls = 0;

  @override
  Future<PaymentLinkClaimInspection> inspectClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) {
    inspectionCalls++;
    return _inspection.future;
  }

  void finishInspection() => _inspection.complete(
    PaymentLinkClaimInspection(
      link: paymentLinkNavigationLink,
      directory: Directory('/tmp/vizor-walletless-gift-navigation-test'),
      dbPath: '/tmp/vizor-walletless-gift-navigation-test/wallet.db',
      accountUuid: 'gift-account',
      totalZatoshi: BigInt.from(110000),
      claimableZatoshi: BigInt.from(100000),
      feeZatoshi: BigInt.from(10000),
      fundingConfirmationCount: kPaymentLinkClaimConfirmationTarget,
      waitingForFundingConfirmations: false,
      availability: PaymentLinkAvailability.available,
    ),
  );

  @override
  Future<void> discardClaimInspection(
    PaymentLinkClaimInspection inspection,
  ) async {}
}

class _FakeIncomingUriService extends IncomingUriService {
  final StreamController<String> _uris = StreamController<String>.broadcast();

  @override
  Stream<String> get uriStream => _uris.stream;

  @override
  Future<void> initialize() async {}

  void emit(String uri) => _uris.add(uri);

  @override
  Future<void> dispose() => _uris.close();
}

final _emptyBootstrap = AppBootstrapState(
  initialLocation: '/welcome',
  initialAccountState: const AccountState(),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
