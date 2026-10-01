@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/payment_links_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_entry_policy.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/features/send/screens/mobile/mobile_send_screen.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';
import 'support/payment_link_navigation_support.dart';

void main() {
  for (final reveal in [false, true]) {
    testWidgets(
      reveal
          ? 'incoming Gift Card waits while the backup phrase is visible'
          : 'incoming Gift Card waits on the backup intro',
      (tester) async {
        tester.view.physicalSize = const Size(520, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _mobileApp(
            accountNotifier: _BackupAccountNotifier(),
            securityNotifier: _BackupSecurityNotifier(),
          ),
        );
        await pumpUntilPresent(tester, find.byType(MobileSendScreen));
        final router = GoRouter.of(
          tester.element(find.byType(MobileSendScreen)),
        );
        unawaited(router.push('/setup/backup', extra: 'account-1'));
        await pumpUntilPresent(tester, find.byType(MobileSeedPhraseScreen));
        await tester.pump(const Duration(milliseconds: 400));
        if (reveal) {
          await tester.tap(
            find.byKey(const ValueKey('mobile_seed_backup_intro_continue')),
          );
          await tester.pump();
          for (final digit in '111111'.split('')) {
            await tester.tap(find.bySemanticsLabel('Digit $digit'));
            await tester.pump();
          }
          expect(find.text('abandon'), findsOneWidget);
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MobileSeedPhraseScreen)),
        );
        container
            .read(paymentLinkIntakeProvider.notifier)
            .receive(paymentLinkNavigationLink.toUri().toString());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(router.state.matchedLocation, '/setup/backup');
        expect(find.byType(MobileSeedPhraseScreen), findsOneWidget);
        expect(find.byType(PaymentLinksScreen), findsNothing);
        expect(
          find.text(kPaymentLinkDeferredByActiveFlowMessage),
          findsOneWidget,
        );
        expect(
          container.read(paymentLinkIntakeProvider).pendingLink,
          isNotNull,
        );
        if (reveal) expect(find.text('abandon'), findsOneWidget);
        router.go('/home');
        await pumpUntilPresent(tester, find.byType(PaymentLinksScreen));
        expect(find.byType(PaymentLinksScreen), findsOneWidget);
      },
    );
  }

  testWidgets('mobile defers a Gift Card until the active send flow is left', (
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
    await pumpUntilPresent(tester, find.byType(MobileSendScreen));
    final sendContext = tester.element(find.byType(MobileSendScreen));
    final container = ProviderScope.containerOf(sendContext);

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MobileSendScreen), findsOneWidget);
    expect(find.text(kPaymentLinkDeferredByActiveFlowMessage), findsOneWidget);
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNotNull);

    GoRouter.of(sendContext).go('/home');
    await pumpUntilPresent(tester, find.byType(PaymentLinksScreen));

    expect(find.byType(PaymentLinksScreen), findsOneWidget);
  });

  testWidgets(
    'mobile Gift Cards opens on the home landing when no link is waiting',
    (tester) async {
      await tester.pumpWidget(_mobileApp());
      await pumpUntilPresent(tester, find.byType(Scaffold));

      final context = tester.element(find.byType(Scaffold).first);
      unawaited(GoRouter.of(context).push('/payment-links'));
      await pumpUntilPresent(tester, find.byType(PaymentLinksScreen));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PaymentLinksHomeMobileView), findsOneWidget);
      expect(find.byType(PaymentLinkRedeemMobileView), findsNothing);
    },
  );

  testWidgets('mobile Gift Cards skips the landing when a link is waiting', (
    tester,
  ) async {
    await tester.pumpWidget(_mobileApp());
    await pumpUntilPresent(tester, find.byType(Scaffold));

    final context = tester.element(find.byType(Scaffold).first);
    // The bootstrap opens on the send screen, where a Gift Card is deferred;
    // the entry decision under test is the one made from the home tab.
    GoRouter.of(context).go('/home');
    await tester.pump(const Duration(milliseconds: 100));
    ProviderScope.containerOf(context)
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await pumpUntilPresent(tester, find.byType(PaymentLinksScreen));

    // The waiting link goes straight into the redeem pre-check — with this
    // fake it resolves at once into the received page — and the landing is
    // never shown on the way.
    expect(find.byType(PaymentLinksHomeMobileView), findsNothing);
    expect(find.byType(PaymentLinkReceivedMobileView), findsOneWidget);
  });
}

Widget _mobileApp({
  AccountNotifier? accountNotifier,
  AppSecurityNotifier? securityNotifier,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(readyPaymentLinkBootstrap),
      if (accountNotifier != null)
        accountProvider.overrideWith(() => accountNotifier),
      if (securityNotifier != null)
        appSecurityProvider.overrideWith(() => securityNotifier),
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
  );
}

class _BackupAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => readyPaymentLinkBootstrap.initialAccountState;

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async => const SoftwareWalletSecret(
    mnemonic:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
  );
}

class _BackupSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}
