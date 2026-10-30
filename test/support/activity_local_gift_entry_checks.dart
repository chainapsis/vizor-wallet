import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/activity_history_pager.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_skeleton_row.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_claim_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_lifecycle_revision.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_recovery_store.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../fakes/fake_sync_notifier.dart';

void activityLocalGiftEntryChecks(
  Widget Function() screen, {
  required bool mobile,
}) {
  test('Gift Card index reads only persisted records', () async {
    final operations = _Operations()..records.add(_record('account-1'));
    final container = ProviderContainer(
      overrides: [paymentLinkOperationsProvider.overrideWithValue(operations)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      giftCardActivityIndexProvider('account-1'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    final index = await container.read(
      giftCardActivityIndexProvider('account-1').future,
    );
    expect(index.createdTxids, {_txid('account-1')});
    expect(operations.localReads, 1);
    expect(operations.legacyRecoveryReads, 0);
    expect(operations.recoveryCalls, 0);
  });

  for (final otherAccount in [false, true]) {
    testWidgets(
      'local rows paint before blocked recovery (other-account draft=$otherAccount)',
      (tester) async {
        final fixture = _Fixture();
        fixture.operations.records.add(_record('account-1'));
        if (otherAccount) {
          fixture.operations.records.add(_record('account-2', ambiguous: true));
        }
        fixture.operations.onRecovery = () {
          expect(find.text('Created a gift card'), findsOneWidget);
          expect(find.byType(ActivitySkeletonRow), findsNothing);
        };
        await fixture.mount(tester, screen, mobile: mobile);
        await _pump(tester);
        expect(fixture.historyReads['account-1'], greaterThanOrEqualTo(1));
        expect(find.text('Created a gift card'), findsOneWidget);
        expect(fixture.operations.recoveryCalls, 1);
        expect(fixture.operations.recovery.isCompleted, isFalse);
        expect(fixture.operations.legacyRecoveryReads, 0);
      },
    );
  }

  testWidgets('local classification is ready before the first history read', (
    tester,
  ) async {
    final fixture = _Fixture();
    final local = Completer<void>();
    fixture.operations.localGate = local;
    fixture.operations.records.add(_record('account-1'));
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    expect(fixture.historyReads, isEmpty);
    expect(fixture.operations.recoveryCalls, 0);
    expect(find.byType(ActivitySkeletonRow), findsWidgets);
    local.complete();
    await _pump(tester);
    expect(find.text('Created a gift card'), findsOneWidget);
    expect(fixture.operations.recoveryCalls, 1);
  });

  testWidgets('recovery updates classification without starting another pass', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    expect(find.byType(ActivityFeedRowGroup), findsOneWidget);
    expect(find.text('Created a gift card'), findsNothing);
    expect(fixture.operations.recoveryCalls, 1);
    fixture.operations.records.add(_record('account-1'));
    fixture.container
        .read(paymentLinkLifecycleRevisionProvider.notifier)
        .bump();
    fixture.operations.recovery.complete(fixture.operations.records);
    await _pump(tester);
    expect(find.text('Created a gift card'), findsOneWidget);
    expect(fixture.operations.recoveryCalls, 1);
    expect(fixture.operations.localReads, greaterThan(1));
  });

  testWidgets('failed recovery keeps the loaded local rows', (tester) async {
    final fixture = _Fixture();
    fixture.operations.records.add(_record('account-1'));
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    fixture.operations.recovery.completeError(StateError('offline'));
    await _pump(tester);
    expect(find.text('Created a gift card'), findsOneWidget);
    expect(find.text('Retry loading activity'), findsNothing);
    expect(fixture.operations.recoveryCalls, 1);
  });

  testWidgets('empty local history also starts deferred recovery', (
    tester,
  ) async {
    final fixture = _Fixture()..emptyHistory = true;
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    expect(find.byType(ActivitySkeletonRow), findsNothing);
    expect(find.byType(ActivityFeedRowGroup), findsNothing);
    expect(fixture.operations.recoveryCalls, 1);
  });

  for (final locked in [false, true]) {
    testWidgets('interrupted recovery resumes once (locked=$locked)', (
      tester,
    ) async {
      final fixture = _Fixture();
      fixture.operations.records.add(_record('account-1'));
      await fixture.mount(tester, screen, mobile: mobile);
      await _pump(tester);
      expect(fixture.operations.recoveryCalls, 1);
      final coordinator = fixture.container.read(
        paymentLinkClaimCoordinatorProvider,
      );
      if (locked) {
        fixture.security.locked = true;
      } else {
        coordinator.pauseForLifecycle();
      }
      final interrupted = fixture.operations.recovery;
      fixture.operations.recovery = Completer();
      interrupted.completeError(
        GiftCardPreparationInterrupted(
          locked
              ? GiftCardPreparationPauseReason.locked
              : GiftCardPreparationPauseReason.lifecycle,
        ),
      );
      await _pump(tester);
      expect(fixture.operations.recoveryCalls, 1);
      expect(find.text('Created a gift card'), findsOneWidget);
      if (locked) {
        fixture.security.locked = false;
      } else {
        coordinator.resumeForLifecycle();
      }
      await _pump(tester);
      expect(fixture.operations.recoveryCalls, 2);
      fixture.operations.recovery.complete(fixture.operations.records);
      await _pump(tester);
      expect(fixture.operations.recoveryCalls, 2);
    });
  }

  testWidgets('late recovery does not publish the previous account rows', (
    tester,
  ) async {
    final fixture = _Fixture();
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    fixture.accounts.select('account-2');
    await _pump(tester);
    expect(fixture.historyReads['account-2'], greaterThanOrEqualTo(1));
    fixture.operations.records.add(_record('account-1'));
    fixture.container
        .read(paymentLinkLifecycleRevisionProvider.notifier)
        .bump();
    fixture.operations.recovery.complete(fixture.operations.records);
    await _pump(tester);
    expect(find.byType(ActivityFeedRowGroup), findsOneWidget);
    expect(find.text('Created a gift card'), findsNothing);
  });

  testWidgets('locking before local history finishes defers recovery', (
    tester,
  ) async {
    final fixture = _Fixture();
    final history = Completer<void>();
    fixture.historyGate = history;
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    fixture.security.locked = true;
    history.complete();
    await _pump(tester);
    expect(fixture.operations.recoveryCalls, 0);
    fixture.security.locked = false;
    await _pump(tester);
    expect(fixture.operations.recoveryCalls, 1);
  });

  testWidgets('leaving before local history finishes never starts recovery', (
    tester,
  ) async {
    final fixture = _Fixture();
    final history = Completer<void>();
    fixture.historyGate = history;
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    await tester.pumpWidget(const SizedBox());
    history.complete();
    await _pump(tester);
    expect(fixture.operations.recoveryCalls, 0);
  });

  testWidgets('covered route waits until visible to start recovery', (
    tester,
  ) async {
    final fixture = _Fixture();
    final history = Completer<void>();
    fixture.historyGate = history;
    await fixture.mount(tester, screen, mobile: mobile);
    await _pump(tester);
    unawaited(fixture.router.push('/other'));
    await _pump(tester);
    history.complete();
    await _pump(tester);
    expect(fixture.operations.recoveryCalls, 0);
    fixture.router.pop();
    await _pump(tester);
    expect(fixture.operations.recoveryCalls, 1);
  });
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _Fixture {
  final operations = _Operations();
  final accounts = _Accounts();
  final security = _Security();
  final historyReads = <String, int>{};
  Completer<void>? historyGate;
  bool emptyHistory = false;
  late ProviderContainer container;
  late GoRouter router;

  Future<void> mount(
    WidgetTester tester,
    Widget Function() screen, {
    required bool mobile,
  }) async {
    await tester.binding.setSurfaceSize(
      mobile ? const Size(390, 844) : const Size(1280, 900),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap),
        accountProvider.overrideWith(() => accounts),
        appSecurityProvider.overrideWith(() => security),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
          ),
        ),
        paymentLinkOperationsProvider.overrideWithValue(operations),
        paymentLinkSetupJournalPendingProvider.overrideWithValue(
          () async => false,
        ),
        // Keep the normal screen constructor and its real metadata provider.
        // Only the native source is replaced, below the production entry path.
        activityHistorySourceFactoryProvider.overrideWithValue(
          (uuid, _) => FixtureActivityHistorySource(() async {
            historyReads.update(uuid, (n) => n + 1, ifAbsent: () => 1);
            await historyGate?.future;
            return emptyHistory ? [] : [_transaction(uuid)];
          }),
        ),
      ],
    );
    await container.read(accountProvider.future);
    router = GoRouter(
      initialLocation: '/activity',
      routes: [
        GoRoute(path: '/activity', builder: (_, _) => screen()),
        GoRoute(path: '/other', builder: (_, _) => const SizedBox()),
      ],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
  }
}

class _Operations implements PaymentLinkOperations {
  final records = <PaymentLinkRecoveryRecord>[];
  var recovery = Completer<List<PaymentLinkRecoveryRecord>>();
  Completer<void>? localGate;
  VoidCallback? onRecovery;
  int localReads = 0;
  int legacyRecoveryReads = 0;
  int recoveryCalls = 0;

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinks() async {
    localReads++;
    await localGate?.future;
    return List.of(records);
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> loadCreatedLinkRecoveries() {
    legacyRecoveryReads++;
    return recovery.future;
  }

  @override
  Future<List<PaymentLinkRecoveryRecord>> recoverCreatedLinks() {
    recoveryCalls++;
    onRecovery?.call();
    return recovery.future;
  }

  @override
  Future<List<PaymentLinkReceivedRecord>> loadReceivedLinkRecoveries() async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _accountState = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Account 2', order: 1),
  ],
  activeAccountUuid: 'account-1',
);

class _Accounts extends AccountNotifier {
  @override
  AccountState build() => _accountState;

  void select(String uuid) =>
      state = AsyncData(state.requireValue.copyWith(activeAccountUuid: uuid));
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  set locked(bool locked) => state = state.copyWith(isUnlocked: !locked);
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

String _txid(String account) => (account == 'account-1' ? 'a' : 'b') * 64;

rust_sync.TransactionInfo _transaction(String account) =>
    rust_sync.TransactionInfo(
      txidHex: _txid(account),
      minedHeight: BigInt.from(3000000),
      expiredUnmined: false,
      accountBalanceDelta: -100000000,
      fee: BigInt.zero,
      feeState: rust_sync.TransactionFeeState.notApplicable,
      detailsComplete: true,
      provisional: false,
      amountIncludesFee: false,
      blockTime: BigInt.from(1764150000),
      isTransparent: false,
      txKind: 'sent',
      displayAmount: BigInt.from(100000000),
      displayPool: 'shielded',
      createdTime: BigInt.from(1764150000),
    );

PaymentLinkRecoveryRecord _record(
  String account, {
  bool ambiguous = false,
}) => PaymentLinkRecoveryRecord(
  link: VizorPaymentLink(
    network: 'main',
    address: 'fixture-$account',
    amountZatoshi: BigInt.from(100000000),
    mnemonic:
        'abandon ability able about above absent absorb abstract absurd abuse access accident',
    birthdayHeight: 1,
    label: 'Gift Card',
    createdAt: DateTime.utc(2026, 8, 28),
  ),
  sourceAccountUuid: account,
  state: ambiguous
      ? PaymentLinkRecoveryState.draft
      : PaymentLinkRecoveryState.funded,
  fundingTxids: ambiguous ? null : _txid(account),
  submittedAtHeight: ambiguous ? 1 : null,
  updatedAt: DateTime.utc(2026, 8, 28),
  claimFeeReserveZatoshi: BigInt.from(10000),
);
