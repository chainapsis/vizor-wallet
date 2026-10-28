@Tags(['mobile'])
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/screens/mobile/mobile_software_shield_screen.dart';
import 'package:zcash_wallet/src/features/home/services/transparent_shielding_service.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/privacy_mode_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart';

void main() {
  for (final status in [
    'broadcasted',
    'pending_broadcast',
    'partial_broadcast',
  ]) {
    testWidgets(
      'software shielding reflects $status without a duplicate send',
      (tester) async {
        final result = Completer<ShieldTransparentResult>();
        var calls = 0;
        final router = GoRouter(
          initialLocation: '/home/shield',
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const Text('Wallet')),
            GoRoute(
              path: '/home/shield',
              builder: (_, _) => const MobileSoftwareShieldScreen(),
            ),
          ],
        );
        addTearDown(router.dispose);
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap()),
            syncProvider.overrideWith(_Sync.new),
            walletProvider.overrideWith(_Wallet.new),
            softwareTransparentShieldRunnerProvider.overrideWithValue(({
              required ref,
              required accountUuid,
              logContext = 'test',
            }) {
              expect(accountUuid, 'account-1');
              calls++;
              return result.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(syncProvider.future);
        await container.read(walletProvider.future);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: AppTheme(
              data: AppThemeData.light,
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(calls, 0);
        expect(find.textContaining('You receive'), findsNothing);
        expect(find.textContaining('Network fee'), findsNothing);
        final slide = find.byKey(const ValueKey('mobile_shield_slide'));
        await tester.dragFrom(
          tester.getTopLeft(slide) + const Offset(35, 30),
          const Offset(280, 0),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(calls, 1);
        expect(
          tester
              .widget<PopScope>(
                find.byWidgetPredicate((widget) => widget is PopScope),
              )
              .canPop,
          isFalse,
        );
        result.complete(
          ShieldTransparentResult(
            txids: 'ab',
            status: status,
            broadcastedCount: status == 'broadcasted' ? 1 : 0,
            totalCount: 1,
            feeZatoshi: BigInt.from(10000),
            shieldedZatoshi: BigInt.from(990000),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 4));
        expect(calls, 1);
        if (status == 'broadcasted') {
          expect(find.text('Shielded successfully'), findsOneWidget);
          expect(find.textContaining('Waiting for confirmation'), findsNothing);
          expect(
            find.byKey(const ValueKey('mobile_shield_complete')),
            findsOneWidget,
          );
        } else {
          expect(find.text('Shielding queued'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('mobile_shield_complete')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final privacyModeEnabled in [false, true]) {
    testWidgets(
      'software shielding amounts with privacy mode $privacyModeEnabled',
      (tester) async {
        tester.view.physicalSize =
            const Size(393, 852) * tester.view.devicePixelRatio;
        addTearDown(tester.view.resetPhysicalSize);
        final result = Completer<ShieldTransparentResult>();
        final router = GoRouter(
          initialLocation: '/home/shield',
          routes: [
            GoRoute(path: '/home', builder: (_, _) => const Text('Wallet')),
            GoRoute(
              path: '/home/shield',
              builder: (_, _) => const MobileSoftwareShieldScreen(),
            ),
          ],
        );
        addTearDown(router.dispose);
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap()),
            privacyModeProvider.overrideWith(
              () => _Privacy(privacyModeEnabled),
            ),
            syncProvider.overrideWith(_Sync.new),
            walletProvider.overrideWith(_Wallet.new),
            softwareTransparentShieldRunnerProvider.overrideWithValue(({
              required ref,
              required accountUuid,
              logContext = 'test',
            }) {
              return result.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(syncProvider.future);
        await container.read(walletProvider.future);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: AppTheme(
              data: AppThemeData.light,
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        MobileShieldScene scene() =>
            tester.widget<MobileShieldScene>(find.byType(MobileShieldScene));
        final amount = privacyModeEnabled ? '******' : '0.01';
        final resultAmount = privacyModeEnabled ? '******' : '0.0099';

        expect(scene().amount, amount);
        expect(find.bySemanticsLabel('$amount ZEC'), findsOneWidget);
        if (privacyModeEnabled) {
          expect(find.bySemanticsLabel(RegExp(r'0\.0')), findsNothing);
        }

        final slide = find.byKey(const ValueKey('mobile_shield_slide'));
        await tester.dragFrom(
          tester.getTopLeft(slide) + const Offset(35, 30),
          const Offset(280, 0),
        );
        await tester.pump(const Duration(milliseconds: 400));
        result.complete(
          ShieldTransparentResult(
            txids: 'ab',
            status: 'broadcasted',
            broadcastedCount: 1,
            totalCount: 1,
            feeZatoshi: BigInt.from(10000),
            shieldedZatoshi: BigInt.from(990000),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 4));
        expect(find.text('Shielded successfully'), findsOneWidget);
        expect(scene().resultAmount, resultAmount);
        expect(find.bySemanticsLabel('$resultAmount ZEC'), findsOneWidget);
        if (privacyModeEnabled) {
          expect(find.bySemanticsLabel(RegExp(r'0\.0')), findsNothing);
        }
        expect(find.bySemanticsLabel(RegExp('ZEC ZEC')), findsNothing);
        semantics.dispose();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Privacy extends PrivacyModeNotifier {
  _Privacy(this.enabled);

  final bool enabled;

  @override
  bool build() => enabled;
}

class _Sync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    transparentBalance: BigInt.from(1000000),
    canShieldTransparentBalance: true,
    shieldTransparentFee: BigInt.from(10000),
    shieldTransparentAmount: BigInt.from(990000),
  );
}

class _Wallet extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(
    hasWallet: true,
    unifiedAddress: 'u1test',
    network: 'main',
    activeAccountUuid: 'account-1',
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/home/shield',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1test',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
