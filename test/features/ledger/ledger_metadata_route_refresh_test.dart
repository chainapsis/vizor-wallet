@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_routes.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/linux_keyring_coordinator.dart';
import 'package:zcash_wallet/src/features/send/services/send_flow.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_navigation.dart';
import 'package:zcash_wallet/src/features/swap/screens/mobile/mobile_swap_ledger_sign_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/providers/router_refresh_provider.dart';

const accounts = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'ledger',
      name: 'Ledger',
      order: 0,
      isHardware: true,
      hardwareSignerKind: HardwareSignerKind.ledger,
      ledgerDeviceId: 'saved',
      zip32AccountIndex: 0,
    ),
  ],
  activeAccountUuid: 'ledger',
  activeAddress: 'u-test',
);
final bootstrap = AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: accounts,
  initialSyncSnapshot: AppSyncSnapshot.emptyForAccount('ledger'),
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

void main() {
  final args = SendReviewArgs(
    proposalId: BigInt.one,
    sendFlowId: 'ledger-flow',
    proposalAccountUuid: 'ledger',
    address: 'u-test',
    addressType: 'unified',
    amountZatoshi: BigInt.one,
    feeZatoshi: BigInt.one,
    needsSaplingParams: false,
  );
  final intent = SwapIntent(
    id: 'ledger-flow',
    pair: 'ZEC/USDC',
    sellAmount: '1',
    receiveEstimate: '1',
    provider: 'test',
    status: SwapIntentStatus.values.first,
    nextAction: 'sign',
  );
  for (final flow in ['send', 'swap', 'pay']) {
    for (final replacement in [false, true]) {
      testWidgets(
        '$flow Ledger metadata keeps live route (replacement=$replacement)',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          final store = AppSecureStore.testing(
            storage: const FlutterSecureStorage(),
            enforceSessionGeneration: false,
          );
          final coordinator = LinuxKeyringCoordinator.testing();
          final container = ProviderContainer(
            overrides: [
              appBootstrapProvider.overrideWithValue(bootstrap),
              linuxKeyringCoordinatorProvider.overrideWithValue(coordinator),
              accountProvider.overrideWith(
                () => AccountNotifier.testing(store: store),
              ),
            ],
          );
          await container.read(walletProvider.future);
          final refresh = container.read(routerRefreshProvider);
          var notifications = 0;
          // Same wallet -> refresh binding used by the application router.
          final subscription = container.listen(walletProvider, (_, _) {
            notifications++;
            refresh.requestRefresh();
          });
          final path = flow == 'send'
              ? '/send/ledger-sign'
              : '/swap/ledger-sign';
          final Object payload = flow == 'send'
              ? args
              : MobileSwapLedgerSignArgs.fromReview(
                  intent: intent,
                  returnTarget: flow == 'pay'
                      ? SwapActivityReturnTarget.pay
                      : SwapActivityReturnTarget.swap,
                );
          final route = buildMobileRoutes(
            entryRoutes: [],
          ).whereType<GoRoute>().singleWhere((r) => r.path == path);
          Object? livePayload;
          // Inspect real production page selection without starting Rust/native IO.
          final router = GoRouter(
            initialLocation: '/home',
            refreshListenable: refresh,
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const Text('home')),
              GoRoute(
                path: path,
                builder: (context, state) {
                  livePayload = state.extra;
                  final page =
                      route.pageBuilder!(context, state)
                          as CustomTransitionPage;
                  expect(page.opaque, isFalse);
                  return Text(page.child.runtimeType.toString());
                },
              ),
            ],
          );
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          router.push<void>(path, extra: payload);
          await tester.pumpAndSettle();
          final screen = flow == 'send'
              ? 'MobileLedgerSendSignScreen'
              : 'MobileSwapLedgerSignScreen';
          expect(find.text(screen), findsOneWidget);
          await container
              .read(accountProvider.notifier)
              .recordLedgerConnection(
                uuid: 'ledger',
                transport: LedgerConnectionTransport.bluetooth,
                deviceId: replacement ? 'replacement' : null,
                deviceName: replacement ? 'New Ledger' : null,
              );
          await tester.pumpAndSettle();
          expect(
            container
                .read(accountProvider)
                .requireValue
                .activeAccount!
                .ledgerDeviceId,
            replacement ? 'replacement' : 'saved',
          );
          expect(
            container
                .read(accountProvider)
                .requireValue
                .activeAccount!
                .ledgerLastTransport,
            LedgerConnectionTransport.bluetooth,
          );
          expect(notifications, 0);
          expect(identical(livePayload, payload), isTrue);
          expect(find.text(screen), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          subscription.close();
          container.dispose();
          coordinator.dispose();
        },
      );
    }
  }
}
