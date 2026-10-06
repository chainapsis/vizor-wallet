import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
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
  setUpAll(loadPaymentLinksTestFonts);
  late ProviderContainer container;
  late _GiftOperations operations;
  late _Accounts accounts;
  late _Security security;
  late PaymentLinkReceivedStore received;

  Future<void> pump(
    WidgetTester tester, {
    bool existing = false,
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
    accounts = _Accounts(existing: existing);
    security = _Security(existing: existing);
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        if (retryBootstrap != null)
          appBootstrapRetryProvider.overrideWithValue(retryBootstrap),
        accountProvider.overrideWith(() => accounts),
        appSecurityProvider.overrideWith(() => security),
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
        await tester.enterText(
          keyed('customise_account_name_field'),
          'My desktop gift',
        );
        await tester.tap(keyed('customise_account_finish_button'));
        await tester.pumpAndSettle();
        expect(find.text('Gift Home'), findsOneWidget);
        expect(accounts.creationCalls, 1);
        expect(security.prepareCalls, existing ? 0 : 1);
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
  }
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
    _passcode = password;
  }

  @override
  String requireSessionPasswordForNativeSecretUse() => _passcode!;

  @override
  Future<void> completePasswordSetup() async => commitPasswordSetup();

  @override
  void commitPasswordSetup() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: true,
  );
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
