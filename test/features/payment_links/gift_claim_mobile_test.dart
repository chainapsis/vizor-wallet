@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_passcode_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_biometrics_screen.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_flow_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/screens/gift_claim_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_clipboard.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_copy.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_claim_outcome_view.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_failure_notice_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_long_sync_warning.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';
import '../../support/payment_link_navigation_support.dart';
import '../../support/payment_links_screen_support.dart'
    show
        FakePaymentLinkClipboard,
        incomingLink,
        loadPaymentLinksTestFonts,
        pumpPaymentLinksScreen;

Finder keyed(String key) => find.byKey(ValueKey(key));

void main() {
  setUpAll(loadPaymentLinksTestFonts);
  late _GiftOperations operations;

  Future<ProviderContainer> pumpWelcome(
    WidgetTester tester, {
    String? clipboard,
    FakePaymentLinkClipboard? paymentClipboard,
    BiometricUnlock? biometric,
    Size size = const Size(393, 852),
    bool restored = false,
    bool multipleRestoredAccounts = false,
    PaymentLinkReceivedStore? receivedStore,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (!restored) FlutterSecureStorage.setMockInitialValues({});
    final store = receivedStore ?? PaymentLinkReceivedStore(_MemoryStorage());
    operations = _GiftOperations(store);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          appBootstrapProvider.overrideWithValue(_noWalletBootstrap),
          accountProvider.overrideWith(
            restored
                ? multipleRestoredAccounts
                      ? _MultipleImportedAccounts.new
                      : _ImportedAccounts.new
                : _NoAccounts.new,
          ),
          appSecurityProvider.overrideWith(
            restored ? _RestoredSecurity.new : _Security.new,
          ),
          biometricUnlockServiceProvider.overrideWithValue(
            biometric ?? _NoBiometrics(),
          ),
          syncProvider.overrideWith(_IdleSync.new),
          paymentLinkOperationsProvider.overrideWithValue(operations),
          paymentLinkReceivedStoreProvider.overrideWithValue(store),
          paymentLinkClipboardProvider.overrideWithValue(
            paymentClipboard ?? FakePaymentLinkClipboard(text: clipboard),
          ),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await pumpUntilPresent(
      tester,
      restored
          ? keyed('mobile_home_receive')
          : find.byType(MobileWelcomeScreen),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Navigator).last)).state.uri.path;

  Future<ProviderContainer> pumpImport(
    WidgetTester tester, {
    int count = 2,
    bool walletLink = true,
    bool withGift = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    final store = PaymentLinkReceivedStore(_MemoryStorage());
    operations = _GiftOperations(store);
    final args = walletLink
        ? SetPasswordScreenArgs.importWalletLink(
            network: 'main',
            accounts: [
              for (var index = 0; index < count; index++)
                LinkedWalletAccountImport(
                  name: 'Imported ${index + 1}',
                  birthdayHeight: 3000000,
                  zip32AccountIndex: index,
                  isHardware: false,
                  isSeedAnchor: index == 0,
                  mnemonic: 'stub mnemonic words',
                ),
            ],
            contacts: const [],
            packageId: 'test-package',
            completionToken: 'test-token',
            keyBytes: List.filled(32, 0),
          )
        : SetPasswordScreenArgs.importWallet(
            mnemonic: 'stub mnemonic words',
            birthdayHeight: 3000000,
            selectedAdditionalAccountIndices: count == 2 ? const [1] : const [],
          );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MobilePasscodeScreen(
            args: args,
            completeWalletLinkPackage:
                ({
                  required packageId,
                  required completionToken,
                  required keyBytes,
                  required importedAccountCount,
                  required importedContactCount,
                }) async {},
          ),
        ),
        GoRoute(
          path: '/onboarding/customise-account',
          builder: (_, state) => MobileCustomiseAccountScreen(
            args: mobileOnboardingPayload(state.extra)! as CustomiseAccountArgs,
          ),
        ),
        GoRoute(
          path: '/onboarding/biometrics',
          builder: (_, _) => const MobileBiometricsScreen(),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('Imported Home')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          appBootstrapProvider.overrideWithValue(_noWalletBootstrap),
          accountProvider.overrideWith(
            () => _NoAccounts(importedAccountCount: count),
          ),
          appSecurityProvider.overrideWith(_Security.new),
          biometricUnlockServiceProvider.overrideWithValue(_FaceBiometrics()),
          syncProvider.overrideWith(_IdleSync.new),
          paymentLinkReceivedStoreProvider.overrideWithValue(store),
          paymentLinkOperationsProvider.overrideWithValue(operations),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) => AppTheme(
            data: AppThemeData.light,
            child: MobileOnboardingProgressFrame(child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    if (withGift) {
      final inspection = await operations.inspectClaim(
        paymentLinkNavigationLink,
      );
      await container
          .read(giftClaimSetupReturnProvider.notifier)
          .begin(
            inspection.link,
            accountUuidsBeforeSetup: const [],
            inspection: inspection,
          );
    }
    for (var round = 0; round < 2; round++) {
      for (final digit in '123456'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();
    if (!walletLink) {
      await tester.tap(keyed('mobile_customise_account_continue'));
      await tester.pumpAndSettle();
    }
    return container;
  }

  testWidgets('a single Wallet Link import starts the gift before Face ID', (
    tester,
  ) async {
    final container = await pumpImport(tester, count: 1);
    expect(find.byType(MobileBiometricsScreen), findsOneWidget);
    expect(keyed('payment_link_claim_account_sheet'), findsNothing);
    expect(operations.claimedDestinations, ['new-account']);
    expect(operations.allowLongSyncChecks, [false]);
    expect(await container.read(giftClaimImportStoreProvider).load(), isNull);
    expect(container.read(giftClaimSetupReturnProvider), isNull);
  });

  for (final walletLink in [true, false]) {
    final method = walletLink ? 'Wallet Link' : 'passphrase';
    testWidgets(
      '$method import claims only into the explicitly selected account',
      (tester) async {
        final container = await pumpImport(tester, walletLink: walletLink);
        expect(keyed('payment_link_claim_account_sheet'), findsOneWidget);
        expect(operations.bindDestinations, isEmpty);
        expect(operations.claimedDestinations, isEmpty);
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isTrue,
        );
        expect(
          (await container.read(paymentLinkReceivedStoreProvider).load())
              .single
              .setupAccountUuid,
          isNull,
        );
        final gate = Completer<void>();
        operations.bindGate = gate;
        await tester.tap(keyed('payment_link_claim_account_second-account'));
        await tester.tap(keyed('payment_link_claim_account_confirm'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileBiometricsScreen), findsOneWidget);
        expect(
          container.read(accountProvider).value?.activeAccountUuid,
          'second-account',
        );
        expect(
          (await container.read(paymentLinkReceivedStoreProvider).load())
              .single
              .setupAccountUuid,
          'second-account',
        );
        expect(operations.bindDestinations, ['second-account']);
        expect(operations.claimedDestinations, isEmpty);
        expect(operations.allowLongSyncChecks, [false]);
        gate.complete();
        await tester.pumpAndSettle();
        expect(operations.claimedDestinations, ['second-account']);
      },
    );

    testWidgets(
      'closing the $method receiving choice continues with an unclaimed card',
      (tester) async {
        final container = await pumpImport(tester, walletLink: walletLink);
        await tester.tap(find.bySemanticsLabel('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(MobileBiometricsScreen), findsOneWidget);
        expect(operations.claimedDestinations, isEmpty);
        final record =
            (await container.read(paymentLinkReceivedStoreProvider).load())
                .single;
        expect(record.setupAccountUuid, isNull);
        expect(record.status, PaymentLinkReceivedStatus.readyToClaim);
        expect(
          await container.read(giftClaimImportStoreProvider).load(),
          isNull,
        );
        expect(container.read(giftClaimSetupReturnProvider), isNull);
        await tester.tap(keyed('mobile_biometrics_not_now'));
        await tester.pumpAndSettle();
        expect(find.text('Imported Home'), findsOneWidget);
      },
    );
  }

  testWidgets('locking during account choice leaves the gift unbound', (
    tester,
  ) async {
    final container = await pumpImport(tester);
    (container.read(appSecurityProvider.notifier) as _Security).lock();
    await tester.tap(keyed('payment_link_claim_account_confirm'));
    await tester.pumpAndSettle();
    expect(keyed('payment_link_claim_account_sheet'), findsOneWidget);
    expect(
      find.text(
        'Couldn’t prepare this gift. Try again or choose another account.',
      ),
      findsOneWidget,
    );
    expect(operations.bindDestinations, isEmpty);
    expect(
      (await container.read(paymentLinkReceivedStoreProvider).load())
          .single
          .setupAccountUuid,
      isNull,
    );
  });

  testWidgets('ordinary Wallet Link import has no gift account choice', (
    tester,
  ) async {
    final container = await pumpImport(tester, withGift: false);
    expect(find.byType(MobileBiometricsScreen), findsOneWidget);
    expect(keyed('payment_link_claim_account_sheet'), findsNothing);
    expect(operations.claimedDestinations, isEmpty);
    expect(
      await container.read(paymentLinkReceivedStoreProvider).load(),
      isEmpty,
    );
  });

  testWidgets('Redeem a card waits for an explicit clipboard paste', (
    tester,
  ) async {
    final clipboard = _CountingClipboard(
      text: paymentLinkNavigationLink.toUri().toString(),
    );
    await pumpWelcome(tester, paymentClipboard: clipboard);

    await tester.tap(keyed('mobile_welcome_redeem_card'));
    await tester.pumpAndSettle();

    expect(find.byType(GiftClaimScreen), findsOneWidget);
    expect(find.text('Paste card link'), findsOneWidget);
    expect(clipboard.readCalls, 0);
    expect(find.text('Gift found'), findsNothing);

    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(clipboard.readCalls, 1);
    expect(find.text('Gift found'), findsOneWidget);
  });

  testWidgets('the initial Gift screen stays below the top safe area', (
    tester,
  ) async {
    const topInset = 55.0;
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding = const FakeViewPadding(top: topInset);
    tester.view.padding = const FakeViewPadding(top: topInset);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    await pumpWelcome(tester);
    await tester.tap(keyed('mobile_welcome_redeem_card'));
    await tester.pumpAndSettle();

    expect(location(tester), '/gift');
    expect(
      tester
          .getTopLeft(find.text('Create wallet by redeeming Vizor Gift Card'))
          .dy,
      greaterThanOrEqualTo(topInset),
    );
  });

  testWidgets('a pasted Card is checked and handed to an existing wallet', (
    tester,
  ) async {
    final container = await pumpWelcome(
      tester,
      clipboard: paymentLinkNavigationLink.toUri().toString(),
    );

    await tester.tap(keyed('mobile_welcome_redeem_card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste card link'));
    await tester.pumpAndSettle();

    expect(find.text('You’ve received a gift!'), findsOneWidget);
    expect(find.text('Gift found'), findsOneWidget);
    expect(keyed('payment_link_reveal_transform'), findsOneWidget);

    await tester.tap(keyed('gift_claim_claim_with_an_existing_wallet'));
    await tester.pumpAndSettle();

    expect(location(tester), '/onboarding/method');
    expect(
      container.read(paymentLinkIntakeProvider).pendingLink,
      isA<VizorPaymentLink>().having(
        (link) => link.hasSameCanonicalPayload(paymentLinkNavigationLink),
        'same Card',
        isTrue,
      ),
    );
    expect(operations.discarded, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(location(tester), '/gift');
    expect(find.text('Gift found'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    for (var frame = 0; frame < 30 && location(tester) != '/welcome'; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(location(tester), '/welcome');
    expect(await GiftClaimImportStore().load(), isNull);
  });

  testWidgets('a wallet made from the Card claims it and opens Home', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();

    await tester.tap(keyed('gift_claim_create_a_wallet_to_claim'));
    await tester.pumpAndSettle();
    expect(location(tester), '/gift/passcode');
    for (var round = 0; round < 2; round++) {
      for (final digit in '135790'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();

    expect(container.read(accountProvider).value?.hasAccounts, isFalse);
    expect(container.read(appSecurityProvider).isPasswordConfigured, isFalse);
    expect(
      (container.read(appSecurityProvider.notifier) as _Security).prepareCalls,
      0,
    );
    expect(
      await container.read(paymentLinkReceivedStoreProvider).load(),
      isEmpty,
    );
    await tester.enterText(
      keyed('mobile_customise_account_name_field'),
      'My gift wallet',
    );
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    expect(operations.bindDestinations, ['new-account']);
    expect(operations.claimedDestinations, ['new-account']);
    final submitted =
        (await container.read(paymentLinkReceivedStoreProvider).load()).single;
    expect(submitted.setupAccountUuid, 'new-account');
    expect(submitted.destinationAccountUuid, 'new-account');
    expect(submitted.status, PaymentLinkReceivedStatus.receiving);
    final index = await container.read(
      giftCardActivityIndexProvider('new-account').future,
    );
    expect(
      index.withPendingClaims(const []).single.txidHex,
      submitted.claimTxids,
    );
    (container.read(syncProvider.notifier) as _IdleSync).emit(
      SyncState(
        accountUuid: 'new-account',
        hasAccountScopedData: true,
        isSyncComplete: true,
      ),
    );
    // The pending Activity label keeps animating while the claim is in flight.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Redeeming a card...'), findsOneWidget);
  });

  Future<ProviderContainer> reachGiftCustomise(WidgetTester tester) async {
    final container = await pumpWelcome(tester, biometric: _FaceBiometrics());
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_claim_create_a_wallet_to_claim'));
    await tester.pumpAndSettle();
    for (var round = 0; round < 2; round++) {
      for (final digit in '135790'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a slow broadcast does not hold Face ID or Home', (tester) async {
    final container = await reachGiftCustomise(tester);
    final broadcast = Completer<void>();
    operations.broadcastGate = broadcast;
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/onboarding/biometrics');
    expect(broadcast.isCompleted, isFalse);
    await tester.tap(keyed('mobile_biometrics_not_now'));
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    final store = container.read(paymentLinkReceivedStoreProvider);
    expect(
      (await store.load()).single.status,
      PaymentLinkReceivedStatus.submitting,
    );
    broadcast.complete();
    await tester.pumpAndSettle();
    expect(
      (await store.load()).single.status,
      PaymentLinkReceivedStatus.receiving,
    );
    expect(operations.claimedDestinations, ['new-account']);
  });

  testWidgets('a post-creation storage failure recovers before Face ID', (
    tester,
  ) async {
    final container = await reachGiftCustomise(tester);
    final accounts = container.read(accountProvider.notifier) as _NoAccounts;
    accounts.creationError = GiftClaimAccountCreatedException(
      'new-account',
      StateError('storage unavailable'),
    );
    accounts.afterRecoverySave = () async {
      // Resume can run after the journal is cleared but before the caller
      // registers its inspection. It must not scan the Card again here.
      await container.read(paymentLinkClaimCoordinatorProvider).refresh();
      expect(operations.allowLongSyncChecks, [false]);
      expect(operations.bindDestinations, isEmpty);
    };
    final broadcast = Completer<void>();
    operations.broadcastGate = broadcast;
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/onboarding/biometrics');
    expect(accounts.creationCalls, 1);
    expect(accounts.recoveryCalls, 1);
    expect(container.read(giftClaimFlowProvider), isNull);
    expect(container.read(appSecurityProvider).isPasswordConfigured, isTrue);
    expect(operations.claimedDestinations, ['new-account']);
    expect(operations.allowLongSyncChecks, [false]);
    final saved =
        (await container.read(paymentLinkReceivedStoreProvider).load()).single;
    expect(saved.setupAccountUuid, 'new-account');
    expect(saved.status, PaymentLinkReceivedStatus.submitting);
    expect(broadcast.isCompleted, isFalse);
    expect(
      (container.read(appSecurityProvider.notifier) as _Security).rollbackCalls,
      0,
    );
    await tester.tap(keyed('mobile_biometrics_not_now'));
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    broadcast.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'failed storage recovery retries the same account on the screen',
    (tester) async {
      final container = await reachGiftCustomise(tester);
      final accounts = container.read(accountProvider.notifier) as _NoAccounts;
      accounts
        ..creationError = GiftClaimAccountCreatedException(
          'new-account',
          StateError('storage unavailable'),
        )
        ..recoveryError = StateError('storage still unavailable');
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(keyed('mobile_customise_account_continue'));
        await tester.pumpAndSettle();
        expect(location(tester), '/gift/customise');
        expect(
          find.text('Couldn’t finish saving your wallet. Try again.'),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(keyed('mobile_customise_account_name_field'))
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<AppButton>(keyed('mobile_customise_account_randomise'))
              .onPressed,
          isNull,
        );
        expect(accounts.creationCalls, 1);
        expect(accounts.recoveryCalls, attempt + 1);
        expect(operations.claimedDestinations, isEmpty);
        expect(
          await container.read(paymentLinkReceivedStoreProvider).load(),
          isEmpty,
        );
      }

      accounts.recoveryError = null;
      await tester.tap(keyed('mobile_customise_account_continue'));
      await tester.pumpAndSettle();
      expect(location(tester), '/onboarding/biometrics');
      expect(accounts.creationCalls, 1);
      expect(accounts.recoveryCalls, 3);
      final security =
          container.read(appSecurityProvider.notifier) as _Security;
      expect(security.prepareCalls, 1);
      expect(security.rollbackCalls, 0);
      expect(operations.claimedDestinations, ['new-account']);
      expect(operations.allowLongSyncChecks, [false]);
    },
  );

  testWidgets('incomplete recovery does not continue without a saved Card', (
    tester,
  ) async {
    final container = await reachGiftCustomise(tester);
    final accounts = container.read(accountProvider.notifier) as _NoAccounts;
    accounts
      ..creationError = GiftClaimAccountCreatedException(
        'new-account',
        StateError('storage unavailable'),
      )
      ..skipRecoverySave = true;
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/gift/customise');
    expect(find.text('Try again'), findsOneWidget);
    expect(operations.claimedDestinations, isEmpty);
    expect(accounts.creationCalls, 1);
    expect(accounts.recoveryCalls, 1);
  });

  testWidgets(
    'locking during a storage retry leaves setup for unlock recovery',
    (tester) async {
      final container = await reachGiftCustomise(tester);
      final accounts = container.read(accountProvider.notifier) as _NoAccounts;
      accounts
        ..creationError = GiftClaimAccountCreatedException(
          'new-account',
          StateError('storage unavailable'),
        )
        ..recoveryError = StateError('storage still unavailable');
      await tester.tap(keyed('mobile_customise_account_continue'));
      await tester.pumpAndSettle();
      expect(location(tester), '/gift/customise');
      expect(
        container.read(giftClaimFlowProvider)?.walletSetupInProgress,
        isTrue,
      );

      (container.read(appSecurityProvider.notifier) as _Security).lock();
      await tester.pumpAndSettle();
      expect(location(tester), '/unlock');
      expect(find.byType(MobileCustomiseAccountScreen), findsNothing);
      expect(container.read(giftClaimFlowProvider), isNull);
      expect(operations.claimedDestinations, isEmpty);
      expect(accounts.creationCalls, 1);
    },
  );

  testWidgets('an unknown DB result asks to reopen and disables recreation', (
    tester,
  ) async {
    final container = await reachGiftCustomise(tester);
    (container.read(accountProvider.notifier) as _NoAccounts).creationError =
        GiftClaimAccountCreatedException(null, StateError('DB unavailable'));
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/gift/customise');
    expect(find.text(kWalletAccountStateUncertainMessage), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(keyed('mobile_customise_account_continue'))
          .onPressed,
      isNull,
    );
    expect(container.read(appSecurityProvider).isPasswordConfigured, isTrue);
  });

  testWidgets('an unconfirmed automatic claim opens Home for recovery', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    operations.claimStatus = PaymentLinkClaimBroadcastStatus.pendingBroadcast;
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_claim_create_a_wallet_to_claim'));
    await tester.pumpAndSettle();
    for (var round = 0; round < 2; round++) {
      for (final digit in '135790'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();

    await tester.enterText(
      keyed('mobile_customise_account_name_field'),
      'My gift wallet',
    );
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    expect(operations.claimedDestinations, ['new-account']);
    expect(container.read(giftClaimFailureNoticeProvider), isNull);
    expect(find.byType(AppToast), findsNothing);
  });

  for (final enable in [true, false]) {
    testWidgets('Gift wallet offers Face ID before Home: enable=$enable', (
      tester,
    ) async {
      final biometric = _FaceBiometrics();
      final container = await pumpWelcome(tester, biometric: biometric);
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(paymentLinkNavigationLink.toUri().toString());
      await tester.pumpAndSettle();
      await tester.tap(keyed('gift_claim_create_a_wallet_to_claim'));
      await tester.pumpAndSettle();
      for (var round = 0; round < 2; round++) {
        for (final digit in '135790'.split('')) {
          await tester.tap(find.bySemanticsLabel('Digit $digit'));
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();
      await tester.enterText(
        keyed('mobile_customise_account_name_field'),
        'My gift wallet',
      );
      await tester.tap(keyed('mobile_customise_account_continue'));
      await tester.pumpAndSettle();

      expect(location(tester), '/onboarding/biometrics');
      expect(find.byType(MobileBiometricsScreen), findsOneWidget);
      expect(
        container.read(accountProvider).value?.activeAccount?.name,
        'My gift wallet',
      );
      expect(container.read(appSecurityProvider).isPasswordConfigured, isTrue);
      expect(operations.claimedDestinations, ['new-account']);
      expect(container.read(giftClaimFailureNoticeProvider), isNull);
      expect(find.byType(AppToast), findsNothing);

      await tester.tap(
        keyed(
          enable ? 'mobile_biometrics_enable' : 'mobile_biometrics_not_now',
        ),
      );
      await tester.pumpAndSettle();
      expect(location(tester), '/home');
      expect(biometric.enabledPasscode, enable ? '135790' : null);
    });
  }

  testWidgets('a wallet made while funding confirms opens Home', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    operations.waiting = true;
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_claim_create_a_wallet_to_claim'));
    await tester.pumpAndSettle();
    for (var round = 0; round < 2; round++) {
      for (final digit in '135790'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
    }
    await tester.pumpAndSettle();

    await tester.enterText(
      keyed('mobile_customise_account_name_field'),
      'My gift wallet',
    );
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    expect(operations.bindDestinations, ['new-account']);
    expect(operations.claimedDestinations, isEmpty);
    expect(operations.retainedClaimAddresses, ['u1giftcard']);
  });

  testWidgets(
    'a binding failure preserves the Card and still continues to Home',
    (tester) async {
      final container = await pumpWelcome(tester, biometric: _FaceBiometrics());
      operations.bindFails = true;
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(paymentLinkNavigationLink.toUri().toString());
      await tester.pumpAndSettle();

      await tester.tap(keyed('gift_claim_create_a_wallet_to_claim'));
      await tester.pumpAndSettle();
      for (var round = 0; round < 2; round++) {
        for (final digit in '135790'.split('')) {
          await tester.tap(find.bySemanticsLabel('Digit $digit'));
          await tester.pump();
        }
      }
      await tester.pumpAndSettle();

      await tester.tap(keyed('mobile_customise_account_continue'));
      await tester.pumpAndSettle();
      expect(location(tester), '/onboarding/biometrics');
      expect(container.read(giftClaimFailureNoticeProvider), isNotNull);
      expect(find.byType(AppToast), findsNothing);
      await tester.pump(const Duration(seconds: 20));
      await tester.tap(keyed('mobile_biometrics_not_now'));
      await tester.pumpAndSettle();
      expect(location(tester), '/home');
      expect(find.text('Couldn’t redeem your gift card.'), findsOneWidget);
      expect(find.text('View card'), findsOneWidget);
      expect(container.read(giftClaimFailureNoticeProvider), isNull);
      final saved =
          (await container.read(paymentLinkReceivedStoreProvider).load())
              .single;
      expect(saved.setupAccountUuid, 'new-account');
      expect(saved.status, PaymentLinkReceivedStatus.readyToClaim);
      final index = GiftCardActivityIndex.forAccount(
        accountUuid: 'new-account',
        createdRecords: const [],
        receivedRecords: [saved],
      );
      expect(index.withPendingClaims(const []), isEmpty);
      await tester.tap(find.text('View card'));
      await tester.pumpAndSettle();
      expect(location(tester), '/payment-links');
      expect(find.byType(PaymentLinkClaimOutcomeView), findsOneWidget);
      expect(find.byType(AppToast), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(location(tester), '/payment-links');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(location(tester), '/home');
      expect(find.byType(AppToast), findsNothing);
    },
  );

  testWidgets('a failure after Home opens shows the toast there', (
    tester,
  ) async {
    final container = await reachGiftCustomise(tester);
    final gate = Completer<void>();
    operations.bindGate = gate;
    operations.bindFails = true;
    await tester.tap(keyed('mobile_customise_account_continue'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('mobile_biometrics_not_now'));
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    expect(find.byType(AppToast), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t redeem your gift card.'), findsOneWidget);
    expect(container.read(giftClaimFailureNoticeProvider), isNull);
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.byType(AppToast), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byType(Navigator).last));
    router.push('/payment-links');
    await tester.pumpAndSettle();
    expect(find.byType(AppToast), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(location(tester), '/home');
    expect(find.byType(AppToast), findsNothing);
  });

  testWidgets('an incoming Card opens over Welcome', (tester) async {
    final container = await pumpWelcome(tester);
    operations.waiting = true;

    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();

    expect(find.byType(GiftClaimScreen), findsOneWidget);
    expect(
      find.text('Waiting for the deposit to confirm · 1 of 2'),
      findsOneWidget,
    );
    expect(find.text('You can create your wallet now.'), findsOneWidget);
  });

  testWidgets('a link received on the empty Gift entry starts checking', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    await tester.tap(keyed('mobile_welcome_redeem_card'));
    await tester.pumpAndSettle();
    expect(find.text('Paste card link'), findsOneWidget);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();
    expect(find.text('Gift found'), findsOneWidget);
    final open = container.read(giftClaimFlowProvider);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();
    expect(container.read(giftClaimFlowProvider), same(open));
    expect(
      container.read(paymentLinkIntakeProvider).pendingLinks,
      hasLength(2),
    );
  });

  testWidgets('wallet import handoff is durable before leaving the Card', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_claim_claim_with_an_existing_wallet'));
    await tester.pumpAndSettle();
    expect(location(tester), '/onboarding/method');
    // A fresh store has no knowledge of the first process's provider state.
    final recovered = await GiftClaimImportStore().load();
    expect(
      recovered?.link.hasSameCanonicalPayload(paymentLinkNavigationLink),
      isTrue,
    );
    expect(recovered?.accountUuidsBeforeSetup, isEmpty);
  });

  testWidgets('restart after import binds and claims the saved Card', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_claim_claim_with_an_existing_wallet'));
    await tester.pumpAndSettle();
    // Lose the first process's queues and inspection, keeping OS secure storage.
    final restarted = await pumpWelcome(tester, restored: true);
    await tester.pumpAndSettle();
    final record =
        (await restarted.read(paymentLinkReceivedStoreProvider).load()).single;
    expect(record.setupAccountUuid, 'new-account');
    expect(record.destinationAccountUuid, 'new-account');
    expect(record.status, PaymentLinkReceivedStatus.receiving);
    expect(operations.claimedDestinations, ['new-account']);
    expect(await restarted.read(giftClaimImportStoreProvider).load(), isNull);
  });

  for (final selected in [false, true]) {
    testWidgets(
      'restart after multi-account import ${selected ? 'honors a saved choice' : 'never guesses a recipient'}',
      (tester) async {
        final container = await pumpWelcome(tester);
        container
            .read(paymentLinkIntakeProvider.notifier)
            .receive(paymentLinkNavigationLink.toUri().toString());
        await tester.pumpAndSettle();
        await tester.tap(keyed('gift_claim_claim_with_an_existing_wallet'));
        await tester.pumpAndSettle();
        final store = container.read(paymentLinkReceivedStoreProvider);
        if (selected) {
          // Simulate termination after the choice is durable but before journal cleanup.
          final handoff = await container
              .read(giftClaimImportStoreProvider)
              .load();
          await store.saveReady(
            handoff!.link,
            setupAccountUuid: 'second-account',
          );
        }
        final restarted = await pumpWelcome(
          tester,
          restored: true,
          multipleRestoredAccounts: true,
          receivedStore: store,
        );
        await tester.pumpAndSettle();
        final record = (await store.load()).single;
        expect(record.setupAccountUuid, selected ? 'second-account' : isNull);
        expect(
          record.status,
          selected
              ? PaymentLinkReceivedStatus.receiving
              : PaymentLinkReceivedStatus.readyToClaim,
        );
        expect(
          operations.claimedDestinations,
          selected ? ['second-account'] : isEmpty,
        );
        expect(
          await restarted.read(giftClaimImportStoreProvider).load(),
          isNull,
        );
      },
    );
  }

  testWidgets('gift choice actions expose button semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpWelcome(tester);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();

    for (final key in [
      'gift_claim_create_a_wallet_to_claim',
      'gift_claim_claim_with_an_existing_wallet',
    ]) {
      final node = tester.getSemantics(keyed(key));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }
    semantics.dispose();
  });

  testWidgets('the Card back reads its sender message and stays flippable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpWelcome(tester);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(incomingLink.toUri().toString());
    await tester.pumpAndSettle();

    await tester.tap(
      find.bySemanticsLabel(kPaymentLinkRevealMessageSemanticLabel),
    );
    await tester.pumpAndSettle();

    final back = find.bySemanticsLabel(
      'Sender message: ${incomingLink.presentation!.message}; '
      'Show gift card front',
    );
    expect(back, findsOneWidget);
    expect(
      tester
          .getSemantics(back)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(kPaymentLinkRevealMessageSemanticLabel),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('closing the Card deletes its claim wallet', (tester) async {
    final container = await pumpWelcome(tester);
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(MobileWelcomeScreen), findsOneWidget);
    expect(operations.discarded, hasLength(1));
    expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
  });

  for (final (description, error, exitLabel) in [
    ('network error', const SocketException('offline'), 'Close'),
    (
      'long scan prompt',
      const PaymentLinkLongSyncConfirmationRequired(),
      'Go back',
    ),
  ]) {
    testWidgets('can leave the gift check after a $description', (
      tester,
    ) async {
      final container = await pumpWelcome(tester);
      final gate = Completer<void>();
      operations.inspectionGate = gate;
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(paymentLinkNavigationLink.toUri().toString());
      await pumpUntilPresent(tester, find.text('Checking the gift…'));

      expect(find.text('Checking the gift…'), findsOneWidget);
      expect(keyed('gift_claim_close_button'), findsNothing);

      gate.completeError(error);
      if (exitLabel == 'Close') {
        await tester.pumpAndSettle();
        expect(keyed('gift_claim_close_button'), findsOneWidget);
        expect(find.text('We couldn’t reach the network.'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Close'));
      } else {
        await pumpUntilPresent(
          tester,
          find.byType(PaymentLinkLongSyncWarningSheet),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(keyed('gift_claim_close_button'), findsNothing);
        await tester.tap(keyed('payment_link_long_sync_sheet_cancel_button'));
      }
      await tester.pumpAndSettle();

      expect(location(tester), '/welcome');
      expect(find.byType(MobileWelcomeScreen), findsOneWidget);
      expect(container.read(giftClaimFlowProvider), isNull);
      expect(container.read(paymentLinkIntakeProvider).pendingLink, isNull);
    });
  }

  testWidgets('an old gift asks in a sheet before starting the long scan', (
    tester,
  ) async {
    final container = await pumpWelcome(tester);
    final gate = Completer<void>();
    operations.inspectionGate = gate;
    container
        .read(paymentLinkIntakeProvider.notifier)
        .receive(paymentLinkNavigationLink.toUri().toString());
    await pumpUntilPresent(tester, find.text('Checking the gift…'));
    gate.completeError(const PaymentLinkLongSyncConfirmationRequired());
    await pumpUntilPresent(
      tester,
      find.byType(PaymentLinkLongSyncWarningSheet),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(operations.allowLongSyncChecks, [false]);
    expect(container.read(accountProvider).value?.hasAccounts, isFalse);
    expect(container.read(appSecurityProvider).isPasswordConfigured, isFalse);
    expect(keyed('gift_claim_close_button'), findsNothing);

    operations.inspectionGate = null;
    await tester.tap(keyed('payment_link_long_sync_sheet_confirm_button'));
    await tester.pumpAndSettle();

    expect(operations.allowLongSyncChecks, [false, true]);
    expect(find.byType(PaymentLinkLongSyncWarningSheet), findsNothing);
    expect(find.text('Gift found'), findsOneWidget);
    expect(container.read(accountProvider).value?.hasAccounts, isFalse);
    expect(container.read(appSecurityProvider).isPasswordConfigured, isFalse);
  });

  testWidgets('a wallet owner reaching /gift lands on Gift Cards', (
    tester,
  ) async {
    await pumpPaymentLinksScreen(tester, logicalSize: const Size(393, 852));
    final router = GoRouter.of(
      tester.element(keyed('payment_links_mobile_screen')),
    );

    router.go('/home');
    await tester.pumpAndSettle();
    router.go('/gift');
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/payment-links');
    expect(find.byType(GiftClaimScreen), findsNothing);
  });

  // Layout checks need the real display fonts; they run last so the rest of
  // the file keeps its usual metrics.
  for (final (size, textScale) in [
    (const Size(393, 852), 1.0),
    (const Size(320, 568), 1.0),
    (const Size(320, 568), 1.4),
  ]) {
    testWidgets(
      'the gift status and actions are visible at $size and ${textScale}x',
      (tester) async {
        await loadFigmaCompareFonts();
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = await pumpWelcome(tester, size: size);
        container
            .read(paymentLinkIntakeProvider.notifier)
            .receive(incomingLink.toUri().toString());
        await tester.pumpAndSettle();

        final status = find.text(
          'Create a wallet or use one you have to claim it.',
        );
        final primary = keyed('gift_claim_create_a_wallet_to_claim');
        final secondary = keyed('gift_claim_claim_with_an_existing_wallet');
        expect(
          tester.getRect(find.text('You’ve received a gift!')).top,
          greaterThanOrEqualTo(
            tester.getRect(keyed('gift_claim_close_button')).bottom,
          ),
        );
        expect(
          tester.getRect(status).bottom,
          lessThanOrEqualTo(tester.getRect(primary).top),
        );
        expect(
          tester.getRect(secondary).bottom,
          lessThanOrEqualTo(size.height),
        );
      },
    );
  }

  for (final size in [const Size(375, 667), const Size(320, 568)]) {
    testWidgets('the gift actions wrap larger text at $size', (tester) async {
      await loadFigmaCompareFonts();
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await pumpWelcome(tester, size: size);
      container
          .read(paymentLinkIntakeProvider.notifier)
          .receive(incomingLink.toUri().toString());
      await tester.pumpAndSettle();

      final existing = keyed('gift_claim_claim_with_an_existing_wallet');
      expect(tester.getRect(existing).bottom, lessThanOrEqualTo(size.height));
      await tester.tap(existing);
      await tester.pumpAndSettle();
      expect(location(tester), '/onboarding/method');
    });
  }
}

class _GiftOperations extends PendingClaimPaymentLinkOperations {
  _GiftOperations(this._store);

  final PaymentLinkReceivedStore _store;
  final discarded = <PaymentLinkClaimInspection>[];
  final bindDestinations = <String>[];
  final claimedDestinations = <String>[];
  final retainedClaimAddresses = <String>[];
  bool waiting = false;
  bool bindFails = false;
  Completer<void>? bindGate;
  Completer<void>? inspectionGate;
  Completer<void>? broadcastGate;
  final allowLongSyncChecks = <bool>[];
  PaymentLinkClaimBroadcastStatus claimStatus =
      PaymentLinkClaimBroadcastStatus.broadcasted;

  @override
  Future<PaymentLinkClaimSession> bindClaimDestination(
    PaymentLinkClaimInspection inspection, {
    required String destinationAccountUuid,
  }) async {
    bindDestinations.add(destinationAccountUuid);
    await bindGate?.future;
    if (bindFails) throw StateError('no receive address');
    return PaymentLinkClaimSession(
      link: inspection.link,
      destinationAddress: 'u1new',
      destinationAccountUuid: destinationAccountUuid,
      directory: inspection.directory,
      dbPath: inspection.dbPath,
      accountUuid: inspection.accountUuid,
      totalZatoshi: inspection.totalZatoshi,
      claimableZatoshi: waiting ? BigInt.zero : inspection.link.amountZatoshi,
      feeZatoshi: BigInt.from(10000),
      waitingForFundingConfirmations: waiting,
      availability: waiting
          ? PaymentLinkAvailability.noBalance
          : PaymentLinkAvailability.available,
    );
  }

  @override
  Future<PaymentLinkClaimResult> claimPreparedLink(
    PaymentLinkClaimSession session,
  ) async {
    claimedDestinations.add(session.destinationAccountUuid);
    const txid =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    await _store.markClaimStarted(
      address: session.link.address,
      destinationAccountUuid: session.destinationAccountUuid,
      priorTxids: const [],
      updatedAt: DateTime.utc(2026, 9, 1),
    );
    await broadcastGate?.future;
    if (claimStatus == PaymentLinkClaimBroadcastStatus.broadcasted) {
      await _store.markReceiving(
        address: session.link.address,
        destinationAccountUuid: session.destinationAccountUuid,
        claimTxids: txid,
        claimSubmittedAt: DateTime.utc(2026, 9, 1),
        claimDestinationPool: 'orchard',
      );
    }
    return PaymentLinkClaimResult(txids: txid, status: claimStatus);
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() =>
      _store.load();

  @override
  Future<void> keepReceivedLink(
    VizorPaymentLink link, {
    String? setupAccountUuid,
  }) => _store.saveReady(link, setupAccountUuid: setupAccountUuid);

  @override
  Future<void> retainPendingClaim(PaymentLinkClaimSession session) async {
    retainedClaimAddresses.add(session.link.address);
  }

  @override
  Future<PaymentLinkClaimInspection> inspectClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    allowLongSyncChecks.add(allowLongSync);
    await inspectionGate?.future;
    return PaymentLinkClaimInspection(
      // Inspection resolves the Card's address and age, as the service does.
      link: link.withResolvedMetadata(
        address: 'u1giftcard',
        createdAt: DateTime.utc(2026, 9, 1),
      ),
      directory: Directory.systemTemp,
      dbPath: '/tmp/claim.db',
      accountUuid: 'claim-account',
      totalZatoshi: link.amountZatoshi + BigInt.from(10000),
      claimableZatoshi: waiting ? BigInt.zero : link.amountZatoshi,
      feeZatoshi: waiting ? BigInt.zero : BigInt.from(10000),
      fundingConfirmationCount: waiting ? 1 : 2,
      waitingForFundingConfirmations: waiting,
      availability: waiting
          ? PaymentLinkAvailability.noBalance
          : PaymentLinkAvailability.available,
    );
  }

  @override
  Future<void> discardClaimInspection(
    PaymentLinkClaimInspection inspection,
  ) async => discarded.add(inspection);
}

class _NoAccounts extends AccountNotifier {
  _NoAccounts({this.importedAccountCount = 1});
  final int importedAccountCount;

  void _importAccounts() {
    state = AsyncData(
      AccountState(
        accounts: [
          const AccountInfo(uuid: 'new-account', name: 'Imported 1', order: 0),
          if (importedAccountCount > 1)
            const AccountInfo(
              uuid: 'second-account',
              name: 'Imported 2',
              order: 1,
            ),
        ],
        activeAccountUuid: 'new-account',
        activeAddress: 'u1new',
      ),
    );
  }

  @override
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String profilePictureId = 'pfp-01',
    List<int> additionalAccountIndices = const [],
  }) async => _importAccounts();

  @override
  Future<LinkedWalletAccountsImportResult> importLinkedWalletAccounts({
    required String network,
    required List<LinkedWalletAccountImport> accountsToImport,
  }) async {
    _importAccounts();
    return LinkedWalletAccountsImportResult(
      importedCount: importedAccountCount,
      skippedDuplicateCount: 0,
    );
  }

  @override
  Future<void> switchAccount(String uuid) async {
    state = AsyncData(
      state.requireValue.copyWith(
        activeAccountUuid: uuid,
        activeAddress: 'u1new',
      ),
    );
  }

  GiftClaimAccountCreatedException? creationError;
  Object? recoveryError;
  bool skipRecoverySave = false;
  int creationCalls = 0;
  int recoveryCalls = 0;
  VizorPaymentLink? _pendingGift;
  Future<void> Function()? afterRecoverySave;
  @override
  AccountState build() => const AccountState();

  @override
  Future<void> clearPendingGiftAccountSetup({
    required String accountUuid,
  }) async {}

  @override
  Future<void> recoverPendingAccountMnemonic() async {
    recoveryCalls++;
    if (recoveryError case final error?) throw error;
    if (skipRecoverySave) return;
    await ref
        .read(paymentLinkReceivedStoreProvider)
        .saveReady(_pendingGift!, setupAccountUuid: 'new-account');
    await afterRecoverySave?.call();
    _pendingGift = null;
  }

  @override
  Future<String> createGiftClaimAccount({
    required String name,
    required String profilePictureId,
    required VizorPaymentLink link,
  }) async {
    creationCalls++;
    if (creationError?.accountUuid == null && creationError != null) {
      throw creationError!;
    }
    _pendingGift = link;
    state = AsyncData(
      AccountState(
        accounts: [
          AccountInfo(
            uuid: 'new-account',
            name: name,
            profilePictureId: profilePictureId,
            order: 0,
            setupPending: true,
          ),
        ],
        activeAccountUuid: 'new-account',
        activeAddress: 'u1new',
      ),
    );
    if (creationError != null) throw creationError!;
    await ref
        .read(paymentLinkReceivedStoreProvider)
        .saveReady(link, setupAccountUuid: 'new-account');
    return 'new-account';
  }
}

class _Security extends AppSecurityNotifier {
  @override
  void lock() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );

  int prepareCalls = 0;
  int rollbackCalls = 0;
  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackCalls++;
  }

  String? _passcode;
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  @override
  Future<void> prepareGiftWalletPasswordSetup(String password) =>
      preparePasswordSetup(password);

  @override
  Future<void> preparePasswordSetup(String password) async {
    prepareCalls++;
    _passcode = password;
  }

  @override
  String requireSessionPasswordForNativeSecretUse() => _passcode!;

  @override
  void commitPasswordSetup() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: true,
  );
}

class _IdleSync extends FakeSyncNotifier {
  _IdleSync() : super(SyncState());

  @override
  bool needsPauseForWalletMutation() => false;
}

class _MemoryStorage implements PaymentLinkReceivedStorage {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String next) async => value = next;
}

final _noWalletBootstrap = AppBootstrapState(
  initialLocation: '/welcome',
  initialAccountState: const AccountState(),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: false,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

class _NoBiometrics extends BiometricUnlock {
  @override
  Future<BiometricAvailability> availability() async =>
      BiometricAvailability.unavailable;
}

class _FaceBiometrics extends BiometricUnlock {
  String? enabledPasscode;

  @override
  Future<BiometricAvailability> availability() async =>
      const BiometricAvailability(
        supported: true,
        enrolled: true,
        kind: BiometricKind.face,
      );

  @override
  Future<void> enable(String passcode) async => enabledPasscode = passcode;
}

class _CountingClipboard extends FakePaymentLinkClipboard {
  _CountingClipboard({super.text});
  int readCalls = 0;
  @override
  Future<String?> readText() {
    readCalls++;
    return super.readText();
  }
}

class _ImportedAccounts extends _NoAccounts {
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'new-account', name: 'Imported', order: 0)],
    activeAccountUuid: 'new-account',
    activeAddress: 'u1new',
  );
}

class _RestoredSecurity extends _Security {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
}

class _MultipleImportedAccounts extends _NoAccounts {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(uuid: 'new-account', name: 'Imported 1', order: 0),
      AccountInfo(uuid: 'second-account', name: 'Imported 2', order: 1),
    ],
    activeAccountUuid: 'new-account',
    activeAddress: 'u1new',
  );
}
