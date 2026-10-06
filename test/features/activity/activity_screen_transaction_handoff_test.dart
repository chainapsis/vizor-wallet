import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/features/activity/activity_eta_provider.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_screen.dart';
import 'package:zcash_wallet/src/features/activity/screens/activity_transaction_status_screen.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../support/wallet_path_read_blocker.dart';

void main() {
  testWidgets(
    'same-epoch failed history refresh withholds ETA until recovery',
    (tester) async {
      final pending = rust_sync.TransactionInfo(
        txidHex: 'pending',
        minedHeight: BigInt.zero,
        expiredUnmined: false,
        accountBalanceDelta: 100000000,
        fee: BigInt.zero,
        blockTime: BigInt.zero,
        isTransparent: false,
        txKind: 'receiving',
        displayAmount: BigInt.from(100000000),
        displayPool: 'shielded',
        createdTime: BigInt.zero,
      );

      final before = SyncState(
        accountUuid: 'account-1',
        hasAccountScopedData: true,
        isSyncComplete: true,
        lastSyncCompletedAt: DateTime.utc(2026, 10, 6),
      );
      final sync = FakeSyncNotifier(before);
      final refreshing = Completer<List<rust_sync.TransactionInfo>>();
      var reads = 0;
      var isRefreshing = false;
      await _pumpActivityScreen(
        tester,
        transaction: pending,
        syncNotifier: sync,
        etaLabels: const {'pending': 'Est. 1–3 min'},
        historyLoader: (_) async {
          reads++;
          return isRefreshing ? refreshing.future : [pending];
        },
      );
      expect(find.text('Est. 1–3 min'), findsOneWidget);
      final initialReads = reads;
      isRefreshing = true;
      sync.emit(before.copyWith(recentTransactions: [_transaction]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(reads, initialReads + 1);
      expect(find.text('Est. 1–3 min'), findsOneWidget);
      expect(find.text('Checking status'), findsNothing);
      refreshing.completeError(StateError('history unavailable'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Est. 1–3 min'), findsNothing);
      isRefreshing = false;
      sync.emit(before.copyWith(recentTransactions: [pending]));
      await tester.pump(const Duration(milliseconds: 300));
      expect(reads, initialReads + 2);
      expect(find.text('Est. 1–3 min'), findsOneWidget);
    },
  );

  for (final newBlock in [false, true]) {
    testWidgets(
      'sync completion refreshes older pending rows (new block: $newBlock)',
      (tester) async {
        final pending = rust_sync.TransactionInfo(
          txidHex: 'pending',
          minedHeight: BigInt.zero,
          expiredUnmined: false,
          accountBalanceDelta: 100000000,
          fee: BigInt.zero,
          blockTime: BigInt.zero,
          isTransparent: false,
          txKind: 'receiving',
          displayAmount: BigInt.from(100000000),
          displayPool: 'shielded',
          createdTime: BigInt.zero,
        );
        final before = SyncState(
          accountUuid: 'account-1',
          hasAccountScopedData: true,
          isSyncComplete: true,
          lastSyncCompletedAt: DateTime.utc(2026, 10, 6),
        );
        final sync = FakeSyncNotifier(before);
        var reads = 0;
        var refreshing = false;
        final refreshed = Completer<List<rust_sync.TransactionInfo>>();
        await _pumpActivityScreen(
          tester,
          transaction: pending,
          syncNotifier: sync,
          etaLabels: const {'pending': 'Est. 1–3 min'},
          historyLoader: (_) async {
            reads++;
            return refreshing ? refreshed.future : [pending];
          },
        );
        expect(find.text('Est. 1–3 min'), findsOneWidget);
        final initialReads = reads;
        refreshing = true;
        sync.emit(
          before.copyWith(
            scannedHeight: newBlock ? 101 : before.scannedHeight,
            chainTipHeight: newBlock ? 101 : before.chainTipHeight,
            lastSyncCompletedAt: DateTime.utc(2026, 10, 6, 0, 1),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(reads, initialReads + 1);
        expect(find.text('Est. 1–3 min'), findsNothing);
        expect(find.text('Checking status'), findsOneWidget);
        refreshed.complete([_transaction]);
        await tester.pumpAndSettle();
        expect(find.text('Received'), findsOneWidget);
        expect(find.text('Est. 1–3 min'), findsNothing);
      },
    );
  }

  testWidgets('Activity replaces the pending pool with ETA', (tester) async {
    await _pumpActivityScreen(
      tester,
      transaction: rust_sync.TransactionInfo(
        txidHex: 'pending',
        minedHeight: BigInt.zero,
        expiredUnmined: false,
        accountBalanceDelta: 100000000,
        fee: BigInt.zero,
        blockTime: BigInt.zero,
        isTransparent: false,
        txKind: 'receiving',
        displayAmount: BigInt.from(100000000),
        displayPool: 'shielded',
        createdTime: BigInt.zero,
      ),
      etaLabels: const {'pending': 'Est. 1–3 min'},
    );
    expect(find.text('Est. 1–3 min'), findsOneWidget);
    expect(find.text('Shielded'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'activity tap opens the summary before destination reads finish',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final history = Completer<List<rust_sync.TransactionInfo>>();
      var reads = 0;
      ActivityTransactionStatusArgs? suppliedArgs;
      final router = GoRouter(
        initialLocation: '/activity',
        routes: [
          GoRoute(
            path: '/activity',
            builder: (_, _) =>
                ActivityScreen(historyLoader: (_) async => [_transaction]),
          ),
          GoRoute(
            path: '/activity/tx/:txid',
            builder: (_, state) {
              suppliedArgs = state.extra as ActivityTransactionStatusArgs;
              return ActivityTransactionStatusScreen(
                args: suppliedArgs!,
                historyLoader: (_) {
                  reads++;
                  return history.future;
                },
                detailLoader: (_, _) async => null,
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap),
            syncProvider.overrideWith(
              () => FakeSyncNotifier(
                SyncState(
                  accountUuid: 'account-1',
                  hasAccountScopedData: true,
                  percentage: 1,
                ),
              ),
            ),
            giftCardActivityIndexProvider.overrideWith(
              (_, _) async => GiftCardActivityIndex.empty,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) =>
                AppTheme(data: AppThemeData.dark, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      WalletPathReadBlocker();
      await tester.tap(find.text('Received'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ActivityTransactionStatusScreen), findsOneWidget);
      expect(find.text('Received successfully'), findsOneWidget);
      expect(history.isCompleted, isFalse);
      expect(reads, 1);
      expect(suppliedArgs!.sourceAccountUuid, 'account-1');
      expect(suppliedArgs!.initialTransaction, same(_transaction));
      expect(suppliedArgs!.initialDetail, isNull);
    },
  );
}

Future<_SwitchableAccountNotifier> _pumpActivityScreen(
  WidgetTester tester, {
  rust_sync.TransactionInfo? transaction,
  Map<String, String>? etaLabels,
  ActivityHistoryLoader? historyLoader,
  FakeSyncNotifier? syncNotifier,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final accountNotifier = _SwitchableAccountNotifier();
  final router = GoRouter(
    initialLocation: '/activity',
    routes: [
      GoRoute(
        path: '/activity',
        builder: (_, _) => ActivityScreen(
          historyLoader:
              historyLoader ?? (_) async => [transaction ?? _transaction],
        ),
      ),
      GoRoute(
        path: '/activity/tx/:txid',
        builder: (_, _) => const Text('transaction status route'),
      ),
    ],
  );

  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (etaLabels != null)
          activityEtaLabelsProvider.overrideWithValue(etaLabels),
        appBootstrapProvider.overrideWithValue(_bootstrap),
        accountProvider.overrideWith(() => accountNotifier),
        syncProvider.overrideWith(
          () =>
              syncNotifier ??
              FakeSyncNotifier(
                SyncState(accountUuid: 'account-1', hasAccountScopedData: true),
              ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      ),
    ),
  );
  if (transaction == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(
    find.text(transaction == null ? 'Received' : 'Receiving ...'),
    findsOneWidget,
  );
  return accountNotifier;
}

class _SwitchableAccountNotifier extends AccountNotifier {
  @override
  AccountState build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Account 1',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
      AccountInfo(
        uuid: 'account-2',
        name: 'Account 2',
        order: 1,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1activityaddress',
  );

  void setActiveAccount(String uuid) {
    state = AsyncData(
      state.requireValue.copyWith(activeAccountUuid: uuid, activeAddress: null),
    );
  }
}

final _transaction = rust_sync.TransactionInfo(
  txidHex: 'a' * 64,
  minedHeight: BigInt.from(3000000),
  expiredUnmined: false,
  accountBalanceDelta: 0,
  fee: BigInt.zero,
  blockTime: BigInt.from(1764150000),
  isTransparent: false,
  txKind: 'received',
  displayAmount: BigInt.from(100000000),
  displayPool: 'shielded',
  createdTime: BigInt.from(1764150000),
);

final _bootstrap = AppBootstrapState(
  initialLocation: '/activity',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
