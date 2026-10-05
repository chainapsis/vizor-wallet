import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
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
