import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/payment_links_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/services/incoming_uri_service.dart';

import 'fakes/fake_sync_notifier.dart';
import 'support/payment_link_navigation_support.dart';

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
    ]) {
      expect(
        paymentLinkEntryBlockedAtLocation(location),
        isFalse,
        reason: location,
      );
    }
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

  testWidgets('opens a queued Gift Card after wallet onboarding reaches Home', (
    tester,
  ) async {
    final accountNotifier = _OnboardingAccountNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_emptyBootstrap),
          accountProvider.overrideWith(() => accountNotifier),
          syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
          paymentLinkOperationsProvider.overrideWithValue(
            PendingClaimPaymentLinkOperations(),
          ),
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

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      find.text(kPaymentLinkDeferredByAccountSetupMessage),
      findsOneWidget,
    );
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    accountNotifier.completeOnboarding();
    await pumpUntilPresent(tester, find.byType(PaymentLinksScreen));

    expect(find.byType(PaymentLinksScreen), findsOneWidget);
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

  void completeOnboarding() {
    state = const AsyncData(
      AccountState(
        accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
        activeAccountUuid: 'account-1',
        activeAddress: 'u1testaddress',
      ),
    );
  }
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
