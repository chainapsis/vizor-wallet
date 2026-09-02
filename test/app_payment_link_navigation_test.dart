import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/payment_links_desktop_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/features/send/screens/send_screen.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';

import 'fakes/fake_sync_notifier.dart';

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
            _PendingClaimPaymentLinkOperations(),
          ),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await _pumpUntilPresent(tester, find.byType(WelcomeScreen));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_paymentLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(
      find.text(kPaymentLinkDeferredByAccountSetupMessage),
      findsOneWidget,
    );
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    accountNotifier.completeOnboarding();
    await _pumpUntilPresent(tester, find.byType(PaymentLinksDesktopScreen));

    expect(find.byType(PaymentLinksDesktopScreen), findsOneWidget);
  });

  testWidgets('defers a Gift Card until the active send flow is left', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_readyBootstrap),
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
            _PendingClaimPaymentLinkOperations(),
          ),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await _pumpUntilPresent(tester, find.byType(SendScreen));
    final sendContext = tester.element(find.byType(SendScreen));
    final container = ProviderScope.containerOf(sendContext);

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(_paymentLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SendScreen), findsOneWidget);
    expect(find.text(kPaymentLinkDeferredByActiveFlowMessage), findsOneWidget);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    GoRouter.of(sendContext).go('/home');
    await _pumpUntilPresent(tester, find.byType(PaymentLinksDesktopScreen));

    expect(find.byType(PaymentLinksDesktopScreen), findsOneWidget);
  });

  testWidgets(
    'mobile defers a Gift Card until the active send flow is left',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_readyBootstrap),
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
              _PendingClaimPaymentLinkOperations(),
            ),
          ],
          child: const ZcashWalletApp(),
        ),
      );
      await _pumpUntilPresent(tester, find.byType(MobileSendScreen));
      final sendContext = tester.element(find.byType(MobileSendScreen));
      final container = ProviderScope.containerOf(sendContext);

      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(_paymentLink.toUri().toString());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(MobileSendScreen), findsOneWidget);
      expect(
        find.text(kPaymentLinkDeferredByActiveFlowMessage),
        findsOneWidget,
      );
      expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

      GoRouter.of(sendContext).go('/home');
      await _pumpUntilPresent(tester, find.byType(PaymentLinksDesktopScreen));

      expect(find.byType(PaymentLinksDesktopScreen), findsOneWidget);
    },
    tags: ['mobile'],
  );
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

class _PendingClaimPaymentLinkOperations implements PaymentLinkOperations {
  @override
  Future<PaymentLinkFundingQuote> quoteMaxFunding({
    required String sourceAccountUuid,
  }) => throw UnimplementedError();

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() async =>
      const [];

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async =>
      const [];

  @override
  Future<Map<String, PaymentLinkFundingProgress>> inspectCreatedLinkFundings(
    List<PaymentLinkRecoveryRecord> records,
  ) async => const {};

  @override
  Future<List<PaymentLinkReceivedRecord>> inspectReceivedLinkClaims(
    List<PaymentLinkReceivedRecord> records,
  ) async => records;

  @override
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async => PaymentLinkClaimSession(
    link: link,
    destinationAddress: 'u1receiver',
    destinationAccountUuid: 'account-1',
    directory: Directory('/tmp/vizor-payment-link-navigation-test'),
    dbPath: '/tmp/vizor-payment-link-navigation-test/wallet.db',
    accountUuid: 'payment-link-account',
    totalZatoshi: link.amountZatoshi,
    claimableZatoshi: link.amountZatoshi,
    feeZatoshi: BigInt.from(kPaymentLinkClaimFeeReserveZatoshi),
    fundingConfirmationCount: kPaymentLinkClaimConfirmationTarget,
  );

  @override
  Future<void> discardClaimSession(PaymentLinkClaimSession session) async {}

  @override
  Future<PaymentLinkFundingQuote> quoteFunding({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
  }) => throw UnimplementedError();

  @override
  Future<PaymentLinkFundingResult> createFundedLink({
    required BigInt amountZatoshi,
    required String sourceAccountUuid,
    PaymentLinkPresentation? presentation,
  }) => throw UnimplementedError();

  @override
  Future<void> retryFundingMetadata({
    required String address,
    required String fundingTxids,
  }) => throw UnimplementedError();

  @override
  Future<PaymentLinkRecoveryRecord> markCreatedLinkShared(
    VizorPaymentLink link,
  ) => throw UnimplementedError();

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) => throw UnimplementedError();

  @override
  Future<PaymentLinkClaimResult> claimLink(VizorPaymentLink link) =>
      throw UnimplementedError();
}

Future<void> _pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

final _paymentLink = VizorPaymentLink(
  network: 'main',
  address: 'u1paymentlinkaddress',
  amountZatoshi: BigInt.from(100000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Payment link',
  createdAt: DateTime.utc(2026, 8, 6),
);

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

final _readyBootstrap = AppBootstrapState(
  initialLocation: '/send',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1testaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
