import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_claim_flow_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/input/app_password_input_source.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/create/customise_account_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_entry_price_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_clipboard.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/router_refresh_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../fakes/fake_password_input_source.dart';
import '../../support/payment_link_navigation_support.dart';
import '../../support/payment_links_screen_support.dart'
    show incomingLink, FakePaymentLinkClipboard, loadPaymentLinksTestFonts;

Finder keyed(String key) => find.byKey(ValueKey(key));

final _routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.read(routerRefreshProvider);
  ref.listen(walletProvider, (_, _) => refresh.requestRefresh());
  ref.listen(appSecurityProvider, (_, _) => refresh.requestRefresh());
  final existing = ref.read(accountProvider).value?.hasAccounts == true;
  final router = GoRouter(
    initialLocation: existing ? '/add-account' : '/welcome',
    refreshListenable: refresh,
    redirect: (_, state) =>
        appRedirect(ref: ref, bootstrap: AppBootstrapState.empty, state: state),
    routes: [
      ...appDesktopOnboardingRoutes(ref),
      GoRoute(path: '/home', builder: (_, _) => const Text('Gift Home')),
      GoRoute(
        path: '/payment-links',
        builder: (_, _) => const Text('Received cards'),
      ),
      GoRoute(
        path: '/unlock',
        builder: (_, _) => const Text('Locked recovery'),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _Accounts extends _NoAccounts {
  _Accounts({this.existing = false});
  final bool existing;
  @override
  AccountState build() => existing
      ? const AccountState(
          accounts: [AccountInfo(uuid: 'original', name: 'Original', order: 0)],
          activeAccountUuid: 'original',
          activeAddress: 'u1original',
        )
      : const AccountState();
}

void main() {
  setUpAll(() async {
    await loadPaymentLinksTestFonts();
    RustLib.initMock(api: _RustApiFake());
  });
  late ProviderContainer container;
  late _GiftOperations operations;
  late _Accounts accounts;
  late _Security security;
  late PaymentLinkReceivedStore received;
  late FakePlatform inputPlatform;
  late FakeStore inputStore;
  late LinuxKeyringCoordinator keyring;

  Future<void> pump(
    WidgetTester tester, {
    bool existing = false,
    int importedAccountCount = 1,
    AppBootstrapRetry? retryBootstrap,
    String? clipboard,
    Completer<void>? inspection,
    Completer<void>? broadcast,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FlutterSecureStorage.setMockInitialValues({});
    received = PaymentLinkReceivedStore(_MemoryStorage());
    operations = _GiftOperations(received)
      ..inspectionGate = inspection
      ..broadcastGate = broadcast;
    accounts = _Accounts(existing: existing)
      ..importedAccountCount = importedAccountCount;
    security = _Security(existing: existing);
    inputPlatform = FakePlatform();
    inputStore = FakeStore();
    keyring = LinuxKeyringCoordinator.testing();
    addTearDown(keyring.dispose);
    final inputSource = AppPasswordInputSource(
      enabled: true,
      platform: inputPlatform,
      store: inputStore,
    );
    addTearDown(inputSource.dispose);
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        if (retryBootstrap != null)
          appBootstrapRetryProvider.overrideWithValue(retryBootstrap),
        accountProvider.overrideWith(() => accounts),
        ledgerStaticCapabilityProvider.overrideWithValue(
          const LedgerCapability.supported(),
        ),
        ledgerAccountImporterProvider.overrideWithValue(
          ({
            required name,
            required account,
            required birthdayHeight,
            required profilePictureId,
          }) => accounts.importAccounts(name, profilePictureId),
        ),
        appSecurityProvider.overrideWith(() => security),
        appPasswordInputSourceProvider.overrideWithValue(inputSource),
        linuxKeyringCoordinatorProvider.overrideWithValue(keyring),
        syncProvider.overrideWith(_IdleSync.new),
        giftCardEntryPriceProvider.overrideWith((_) async => null),
        paymentLinkOperationsProvider.overrideWithValue(operations),
        paymentLinkReceivedStoreProvider.overrideWithValue(received),
        paymentLinkClipboardProvider.overrideWithValue(
          FakePaymentLinkClipboard(text: clipboard),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(accountProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(_routerProvider),
          builder: (context, child) => AppTheme(
            data: AppThemeData.dark,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: AppToastHost(child: child!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester) async {
    await tester.tap(keyed('welcome_redeem_card_button'));
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_desktop_paste_button'));
    await tester.pump();
  }

  Future<void> openFirstAccountCustomise(WidgetTester tester) async {
    await paste(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a wallet to claim'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).at(0), 'Password1!');
    await tester.enterText(find.byType(EditableText).at(1), 'Password1!');
    await tester.pump();
    await tester.tap(keyed('set_password_submit_button'));
    await tester.pumpAndSettle();
    expect(container.read(_routerProvider).state.uri.path, '/gift/customise');
  }

  Future<void> openGiftImport(
    WidgetTester tester, {
    bool existing = false,
    int count = 1,
  }) async {
    await pump(
      tester,
      existing: existing,
      importedAccountCount: count,
      clipboard: incomingLink.toUri().toString(),
    );
    await paste(tester);
    await tester.pumpAndSettle();
    await tester.tap(keyed('gift_claim_claim_with_an_existing_wallet'));
    await tester.pumpAndSettle();
    expect(
      container.read(_routerProvider).state.uri.toString(),
      '/import/method?from=gift',
    );
    expect(
      (await container.read(giftClaimImportStoreProvider).load())
          ?.accountUuidsBeforeSetup,
      existing ? {'original'} : isEmpty,
    );
  }

  Future<void> finishImport(
    WidgetTester tester, {
    String method = 'passphrase',
    bool first = true,
    bool gift = true,
  }) async {
    final setup = method == 'keystone'
        ? const SetPasswordScreenArgs.importKeystone(
            name: 'Keystone',
            ufvk: 'preview-ufvk',
            seedFingerprint: [1],
            zip32Index: 0,
            birthdayHeight: 3000000,
          )
        : const SetPasswordScreenArgs.importWallet(
            mnemonic: 'stub mnemonic',
            birthdayHeight: 3000000,
            selectedAdditionalAccountIndices: [1],
          );
    final suffix = gift ? '?entry=import-method&from=gift' : '';
    final router = container.read(_routerProvider);
    if (method == 'ledger') {
      router.go(
        '/onboarding/ledger/customise-account$suffix',
        extra: LedgerCustomiseAccountArgs(
          account: const LedgerDeviceAccount(
            ufvk: 'preview-ledger',
            seedFingerprint: [1],
            accountIndex: 0,
            appVersion: '3.9.3',
          ),
          birthdayHeight: 3000000,
          pendingPassword: first ? 'Password1!' : null,
        ),
      );
    } else {
      router.go(
        '${method == 'keystone' ? '/onboarding/keystone' : '/import'}/customise-account$suffix',
        extra: CustomiseAccountArgs(
          setupArgs: setup,
          pendingPassword: first ? 'Password1!' : null,
        ),
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(keyed('customise_account_finish_button'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Gift import selectors retain their origin and Cancel removes the durable handoff',
    (tester) async {
      await openGiftImport(tester, existing: true);
      final request = container.read(giftClaimSetupReturnProvider);
      await tester.tap(keyed('desktop_import_secret_passphrase_card'));
      await tester.pumpAndSettle();
      expect(
        container.read(_routerProvider).state.uri.toString(),
        '/import?entry=import-method&from=gift',
      );
      await tester.tap(find.text('Import methods'));
      await tester.pumpAndSettle();
      expect(
        container.read(_routerProvider).state.uri.toString(),
        '/import/method?from=gift',
      );
      await tester.tap(keyed('desktop_import_hardware_card'));
      await tester.pumpAndSettle();
      expect(
        container.read(_routerProvider).state.uri.toString(),
        '/import/hardware?from=gift',
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(
        container.read(_routerProvider).state.uri.toString(),
        '/import/method?from=gift',
      );
      expect(container.read(giftClaimSetupReturnProvider), same(request));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        container.read(_routerProvider).state.uri.toString(),
        '/gift?addAccount=true',
      );
      expect(container.read(giftClaimSetupReturnProvider), isNull);
      expect(await container.read(giftClaimImportStoreProvider).load(), isNull);
      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(operations.allowLongSyncChecks, [false]);
    },
  );

  for (final method in ['passphrase', 'keystone', 'ledger']) {
    for (final existing in [false, true]) {
      testWidgets(
        '$method Gift import pins the sole new account and releases setup ownership: existing=$existing',
        (tester) async {
          await openGiftImport(tester, existing: existing);
          operations.bindGate = Completer<void>();
          await finishImport(tester, method: method, first: !existing);
          expect(find.text('Gift Home'), findsOneWidget);
          expect(keyed('payment_link_claim_account_sheet'), findsNothing);
          expect((await received.load()).single.setupAccountUuid, 'imported-0');
          expect(operations.bindDestinations, ['imported-0']);
          expect(operations.claimedDestinations, isEmpty);
          expect(operations.allowLongSyncChecks, [false]);
          expect(accounts.importCalls, 1);
          expect(accounts.importedUnderOwnership, isTrue);
          expect(security.prepareCalls, existing ? 0 : 1);
          if (!existing) expect(security.committedUnderOwnership, isTrue);
          expect(keyring.hasPendingMutation, isFalse);
          expect(
            await container.read(giftClaimImportStoreProvider).load(),
            isNull,
          );
          expect(container.read(giftClaimSetupReturnProvider), isNull);
          operations.bindGate!.complete();
          await tester.pumpAndSettle();
          expect(operations.claimedDestinations, ['imported-0']);
          container.read(paymentLinkClaimCoordinatorProvider).pause();
        },
      );
    }
  }

  for (final close in [false, true]) {
    testWidgets(
      'multiple imported accounts ${close ? 'retain an unclaimed card on close' : 'claim only into the selected account'}',
      (tester) async {
        await openGiftImport(tester, existing: true, count: 2);
        await finishImport(tester, first: false);
        expect(keyed('payment_link_claim_account_sheet'), findsOneWidget);
        expect(keyed('payment_link_claim_account_original'), findsNothing);
        expect((await received.load()).single.setupAccountUuid, isNull);
        expect(keyring.hasPendingMutation, isFalse);
        expect(operations.bindDestinations, isEmpty);
        if (close) {
          await tester.tap(keyed('payment_link_claim_account_close'));
        } else {
          await tester.tap(keyed('payment_link_claim_account_imported-1'));
          await tester.tap(keyed('payment_link_claim_account_confirm'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Gift Home'), findsOneWidget);
        expect(
          (await received.load()).single.setupAccountUuid,
          close ? null : 'imported-1',
        );
        expect(
          operations.claimedDestinations,
          close ? isEmpty : ['imported-1'],
        );
        expect(
          container.read(accountProvider).value?.activeAccountUuid,
          close ? 'imported-0' : 'imported-1',
        );
        expect(
          await container.read(giftClaimImportStoreProvider).load(),
          isNull,
        );
        expect(keyring.hasPendingMutation, isFalse);
        container.read(paymentLinkClaimCoordinatorProvider).pause();
      },
    );
  }

  testWidgets(
    'import failure preserves the Gift journal and a retry uses the original inspection',
    (tester) async {
      await openGiftImport(tester);
      accounts.importError = StateError('connection unavailable');
      await finishImport(tester);
      expect(find.text('Gift Home'), findsNothing);
      expect(
        await container.read(giftClaimImportStoreProvider).load(),
        isNotNull,
      );
      expect(await received.load(), isEmpty);
      expect(keyring.hasPendingMutation, isFalse);
      accounts.importError = null;
      await tester.tap(keyed('customise_account_finish_button'));
      await tester.pumpAndSettle();
      expect(find.text('Gift Home'), findsOneWidget);
      expect(accounts.importCalls, 2);
      expect(operations.allowLongSyncChecks, [false]);
      expect(operations.claimedDestinations, ['imported-0']);
      container.read(paymentLinkClaimCoordinatorProvider).pause();
    },
  );

  for (final method in ['passphrase', 'ledger']) {
    testWidgets(
      '$method import rejects a stale Linux submit before credential preparation',
      (tester) async {
        await openGiftImport(tester);
        final gate = Completer<void>();
        final pending = keyring.runMutation(() => gate.future);
        await finishImport(tester, method: method);
        expect(security.prepareCalls, 0);
        expect(accounts.importCalls, 0);
        expect(find.text('Gift Home'), findsNothing);
        expect(
          await container.read(giftClaimImportStoreProvider).load(),
          isNotNull,
        );
        gate.complete();
        await pending;
        await tester.tap(keyed('customise_account_finish_button'));
        await tester.pumpAndSettle();
        expect(find.text('Gift Home'), findsOneWidget);
        expect(keyring.hasPendingMutation, isFalse);
        container.read(paymentLinkClaimCoordinatorProvider).pause();
      },
    );
  }

  testWidgets(
    'ordinary Ledger import has no Gift handoff and releases its mutation owner',
    (tester) async {
      await pump(tester);
      await finishImport(tester, method: 'ledger', gift: false);
      expect(find.text('Gift Home'), findsOneWidget);
      expect(accounts.importedUnderOwnership, isTrue);
      expect(await received.load(), isEmpty);
      expect(keyring.hasPendingMutation, isFalse);
    },
  );

  testWidgets('invalid card remains on the desktop entry with paste retry', (
    tester,
  ) async {
    await pump(tester, clipboard: 'not a gift card');
    await paste(tester);
    await tester.pumpAndSettle();
    expect(keyed('gift_desktop_paste_button'), findsOneWidget);
    expect(accounts.creationCalls, 0);
    expect(container.read(_routerProvider).state.uri.path, '/gift');
  });

  testWidgets(
    'checking hides card value and blocks setup until inspection completes',
    (tester) async {
      final checking = Completer<void>();
      await pump(
        tester,
        clipboard: incomingLink.toUri().toString(),
        inspection: checking,
      );
      await paste(tester);
      await tester.pump();
      expect(find.text('You’ve received a gift!'), findsNothing);
      final create = keyed('gift_claim_create_a_wallet_to_claim');
      expect(
        tester
            .widget<AppButton>(
              find.descendant(of: create, matching: find.byType(AppButton)),
            )
            .onPressed,
        isNull,
      );
      expect(keyed('gift_claim_close_button'), findsNothing);
      checking.complete();
      await tester.pumpAndSettle();
      expect(find.text('You’ve received a gift!'), findsOneWidget);
      expect(accounts.creationCalls, 0);
    },
  );

  for (final confirm in [false, true]) {
    testWidgets(
      'desktop long-scan consent exits or rechecks explicitly, confirm=$confirm',
      (tester) async {
        final gate = Completer<void>();
        await pump(
          tester,
          clipboard: incomingLink.toUri().toString(),
          inspection: gate,
        );
        await paste(tester);
        gate.completeError(const PaymentLinkLongSyncConfirmationRequired());
        await tester.pumpAndSettle();
        expect(keyed('payment_link_long_sync_confirm_button'), findsOneWidget);
        expect(accounts.creationCalls, 0);
        operations.inspectionGate = null;
        await tester.tap(
          keyed(
            confirm
                ? 'payment_link_long_sync_confirm_button'
                : 'payment_link_long_sync_cancel_button',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          operations.allowLongSyncChecks,
          confirm ? [false, true] : [false],
        );
        expect(
          container.read(_routerProvider).state.uri.path,
          confirm ? '/gift' : '/welcome',
        );
        if (confirm) {
          expect(find.text('You’ve received a gift!'), findsOneWidget);
        }
        expect(accounts.creationCalls, 0);
      },
    );
  }

  testWidgets(
    'partially saved Gift retries startup recovery without creating another account',
    (tester) async {
      var reloads = 0;
      await pump(
        tester,
        existing: true,
        clipboard: incomingLink.toUri().toString(),
        retryBootstrap: () async {
          reloads++;
        },
      );
      accounts.creationError = GiftClaimAccountCreatedException(
        'new-account',
        StateError('metadata write failed'),
      );
      accounts.recoveryError = StateError('storage unavailable');
      await paste(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create an account to claim'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('customise_account_finish_button'));
      await tester.pumpAndSettle();
      expect(find.text('Retry setup'), findsOneWidget);
      expect(accounts.creationCalls, 1);
      await tester.tap(find.text('Retry setup'));
      await tester.pumpAndSettle();
      expect(reloads, 1);
      expect(find.text('Locked recovery'), findsOneWidget);
      expect(accounts.creationCalls, 1);
      expect(security.prepareCalls, 0);
      expect(operations.bindDestinations, isEmpty);
      container.read(paymentLinkClaimCoordinatorProvider).pause();
    },
  );

  for (final existing in [false, true]) {
    testWidgets(
      'desktop Gift commits setup and reaches Home without awaiting broadcast, existing=$existing',
      (tester) async {
        final broadcast = Completer<void>();
        await pump(
          tester,
          existing: existing,
          clipboard: incomingLink.toUri().toString(),
          broadcast: broadcast,
        );
        await paste(tester);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            existing
                ? 'Create an account to claim'
                : 'Create a wallet to claim',
          ),
        );
        await tester.pumpAndSettle();
        if (!existing) {
          expect(
            container.read(_routerProvider).state.uri.path,
            '/gift/set-password',
          );
          await tester.enterText(find.byType(EditableText).at(0), 'Password1!');
          await tester.enterText(find.byType(EditableText).at(1), 'Password1!');
          await tester.pump();
          await tester.tap(keyed('set_password_submit_button'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(CustomiseAccountScreen), findsOneWidget);
        expect(
          container.read(_routerProvider).state.uri.path,
          '/gift/customise',
        );
        expect(accounts.creationCalls, 0);
        expect(inputStore.writes, 0);
        inputPlatform.current = const {
          'platform': 'macos',
          'id': 'another.layout',
        };
        await tester.enterText(
          keyed('customise_account_name_field'),
          'My desktop gift',
        );
        await tester.tap(keyed('customise_account_finish_button'));
        await tester.pumpAndSettle();
        expect(find.text('Gift Home'), findsOneWidget);
        expect(accounts.creationCalls, 1);
        expect(security.prepareCalls, existing ? 0 : 1);
        expect(security.state.isUnlocked, isTrue);
        expect(keyring.hasPendingMutation, isFalse);
        expect(inputStore.writes, existing ? 0 : 1);
        if (!existing) {
          expect(jsonDecode(inputStore.value!)['source'], source);
        }
        expect(
          accounts.state.requireValue.accounts.map((a) => a.uuid),
          existing ? ['original', 'new-account'] : ['new-account'],
        );
        expect(
          accounts.state.requireValue.activeAccount!.name,
          'My desktop gift',
        );
        expect((await received.load()).single.setupAccountUuid, 'new-account');
        expect(operations.bindDestinations, ['new-account']);
        broadcast.complete();
        await tester.pumpAndSettle();
        container.read(paymentLinkClaimCoordinatorProvider).pause();
      },
    );
  }

  testWidgets(
    'failed Gift setup remembers the submitted input source only after retry commits',
    (tester) async {
      await pump(tester, clipboard: incomingLink.toUri().toString());
      await paste(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a wallet to claim'));
      await tester.pumpAndSettle();
      const submittedSource = {'platform': 'windows', 'hkl': 'test.layout'};
      inputPlatform.current = submittedSource;
      await tester.enterText(find.byType(EditableText).at(0), 'Password1!');
      await tester.enterText(find.byType(EditableText).at(1), 'Password1!');
      await tester.pump();
      await tester.tap(keyed('set_password_submit_button'));
      await tester.pumpAndSettle();
      expect(inputStore.writes, 0);
      security.prepareError = StateError('Password preparation unavailable');
      await tester.tap(keyed('customise_account_finish_button'));
      await tester.pumpAndSettle();
      expect(container.read(_routerProvider).state.uri.path, '/gift/customise');
      expect(accounts.creationCalls, 0);
      expect(inputStore.writes, 0);
      expect(security.state.isUnlocked, isFalse);
      expect(keyring.hasPendingMutation, isFalse);

      inputPlatform.current = const {
        'platform': 'windows',
        'hkl': 'another.layout',
      };
      security.prepareError = null;
      await tester.tap(keyed('customise_account_finish_button'));
      await tester.pumpAndSettle();
      expect(find.text('Gift Home'), findsOneWidget);
      expect(accounts.creationCalls, 1);
      expect(security.state.isUnlocked, isTrue);
      expect(keyring.hasPendingMutation, isFalse);
      expect(inputStore.writes, 1);
      expect(jsonDecode(inputStore.value!)['source'], submittedSource);
      container.read(paymentLinkClaimCoordinatorProvider).pause();
    },
  );

  for (final recovering in [false, true]) {
    testWidgets(
      'Linux Gift rejects setup before password work while busy, recovering=$recovering',
      (tester) async {
        await pump(tester, clipboard: incomingLink.toUri().toString());
        await openFirstAccountCustomise(tester);
        final otherWork = Completer<void>();
        Future<void>? pending;
        if (recovering) {
          keyring.setStateForTesting(
            const LinuxKeyringState(phase: LinuxKeyringPhase.keyringLocked),
          );
        } else {
          pending = keyring.runMutation(() => otherWork.future);
        }

        await tester.tap(keyed('customise_account_finish_button'));
        await tester.pumpAndSettle();
        expect(security.prepareCalls, 0);
        expect(accounts.creationCalls, 0);
        expect(inputStore.writes, 0);
        expect(
          container.read(_routerProvider).state.uri.path,
          '/gift/customise',
        );
        expect(
          find.text(
            'Finish the current wallet operation before starting another.',
          ),
          findsOneWidget,
        );

        if (recovering) {
          keyring.setStateForTesting(const LinuxKeyringState());
        } else {
          otherWork.complete();
          await pending;
        }
        await tester.tap(keyed('customise_account_finish_button'));
        await tester.pumpAndSettle();
        expect(find.text('Gift Home'), findsOneWidget);
        expect(security.prepareCalls, 1);
        expect(accounts.creationCalls, 1);
        expect(keyring.hasPendingMutation, isFalse);
        container.read(paymentLinkClaimCoordinatorProvider).pause();
      },
    );
  }

  testWidgets(
    'Linux Gift owns preparation through commit and releases after Home',
    (tester) async {
      await pump(tester, clipboard: incomingLink.toUri().toString());
      await openFirstAccountCustomise(tester);
      final preparation = Completer<void>();
      security.prepareGate = preparation;
      await tester.tap(keyed('customise_account_finish_button'));
      await tester.pump();
      expect(security.prepareCalls, 1);
      expect(accounts.creationCalls, 0);
      expect(keyring.hasPendingMutation, isTrue);
      await expectLater(
        keyring.runMutation(() async => fail('interleaved wallet mutation')),
        throwsA(isA<LinuxWalletMutationBusyException>()),
      );
      preparation.complete();
      await tester.pumpAndSettle();
      expect(find.text('Gift Home'), findsOneWidget);
      expect(accounts.creationCalls, 1);
      expect(security.committedUnderOwnership, isTrue);
      expect(keyring.hasPendingMutation, isFalse);
      expect(
        await keyring.runMutation(() async => 'next operation'),
        'next operation',
      );
      container.read(paymentLinkClaimCoordinatorProvider).pause();
    },
  );
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
  Future<PaymentLinkClaimSession> prepareClaim(
    VizorPaymentLink link, {
    bool allowLongSync = false,
  }) async {
    final saved = await _store.find(link.address);
    return bindClaimDestination(
      await inspectClaim(link, allowLongSync: allowLongSync),
      destinationAccountUuid: saved?.setupAccountUuid ?? 'new-account',
    );
  }

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
  @override
  Future<void> switchAccount(String uuid) =>
      ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
        state = AsyncData(
          state.requireValue.copyWith(
            activeAccountUuid: uuid,
            activeAddress: 'u1new',
          ),
        );
      });

  int importedAccountCount = 1;
  int importCalls = 0;
  Object? importError;
  bool importedUnderOwnership = false;

  Future<void> importAccounts(String? name, String? picture) =>
      ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
        importCalls++;
        importedUnderOwnership = ref
            .read(linuxKeyringCoordinatorProvider)
            .hasPendingMutation;
        if (importError case final error?) throw error;
        state = AsyncData(
          AccountState(
            accounts: [
              ...?state.value?.accounts,
              for (var i = 0; i < importedAccountCount; i++)
                AccountInfo(
                  uuid: 'imported-$i',
                  name: i == 0 ? name ?? 'Imported' : 'Imported $i',
                  order: i,
                  profilePictureId: picture ?? 'default',
                ),
            ],
            activeAccountUuid: 'imported-0',
            activeAddress: 'u1imported',
          ),
        );
      });

  @override
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String? profilePictureId,
    List<int> additionalAccountIndices = const [],
  }) => importAccounts(name, profilePictureId);

  @override
  Future<void> importKeystoneAccount({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
    required int birthdayHeight,
    String? profilePictureId,
  }) => importAccounts(name, profilePictureId);

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
  }) => ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
    creationCalls++;
    if (creationError?.accountUuid == null && creationError != null) {
      throw creationError!;
    }
    _pendingGift = link;
    state = AsyncData(
      AccountState(
        accounts: [
          ...?state.value?.accounts.where((a) => a.uuid != 'new-account'),
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
  });
}

class _Security extends AppSecurityNotifier {
  _Security({this.existing = false});
  final bool existing;

  @override
  void lock() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );

  int prepareCalls = 0;
  int rollbackCalls = 0;
  Object? prepareError;
  Completer<void>? prepareGate;
  bool committedUnderOwnership = false;
  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackCalls++;
  }

  String? _passcode;
  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: existing, isUnlocked: existing);

  @override
  Future<void> preparePasswordSetup(String password) async {
    prepareCalls++;
    if (prepareError case final error?) throw error;
    await prepareGate?.future;
    _passcode = password;
  }

  @override
  String requireSessionPasswordForNativeSecretUse() => _passcode!;

  @override
  Future<void> completePasswordSetup() async => commitPasswordSetup();

  @override
  void commitPasswordSetup() {
    committedUnderOwnership = ref
        .read(linuxKeyringCoordinatorProvider)
        .hasPendingMutation;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }
}

class _IdleSync extends FakeSyncNotifier {
  _IdleSync() : super(SyncState());

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async => const WalletMutationSyncPause(
    hadActiveSync: false,
    hadPolling: false,
    hadMempoolObserver: false,
  );

  @override
  void resumeAfterWalletMutation(
    WalletMutationSyncPause pause, {
    bool forceRestart = false,
  }) {}

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

class _RustApiFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => const ['abandon', 'about'];
  @override
  void crateApiKeystoneResetUrSession() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
