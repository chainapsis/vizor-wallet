import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/mobile_regtest_flow.dart';

const _backgroundMigrationChannel = MethodChannel(
  'com.zcash.wallet/background_migration',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'native background cycle submits one due child while Flutter is paused',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(() async {
        _resumeApp(tester);
        await _revokeAllBackgroundMigrationAuthorization(ignoreErrors: true);
        await cleanupE2eWalletState();
      });
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await _revokeAllBackgroundMigrationAuthorization();
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '1.23 $mobileE2eTicker');

      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      await _waitForIdleSync(
        tester,
        container,
        (initialChain['zcashdHeight'] as num).toInt(),
      );

      await postDriver('/activate', const {});
      await _waitForIronwoodSync(tester, container);
      await openMobilePrivateMigrationReview(tester);
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );

      final accountUuid = await accountUuidAtOrder(0);
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'background migration denomination run',
      );
      expect(started.activeRunId, isNotNull);

      // Make the denomination stage trusted and every regtest schedule offset
      // due before Flutter yields control to the native background runner.
      await postDriver('/mine', const {'blocks': 50});
      final submittedBefore =
          started.broadcastedTxCount + started.confirmedTxCount;

      _pauseApp(tester);
      final result = await _backgroundMigrationChannel
          .invokeMapMethod<String, Object?>('runOnceForTesting');
      final after = await mobileRegtestMigrationStatus(accountUuid);

      expect(result?['outcome'], 'advanced');
      expect(
        after.broadcastedTxCount + after.confirmedTxCount,
        submittedBefore + 1,
      );
      expect(after.activeRunId, started.activeRunId);
      expect(after.totalCount, started.totalCount);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<void> _revokeAllBackgroundMigrationAuthorization({
  bool ignoreErrors = false,
}) async {
  try {
    final revoked = await _backgroundMigrationChannel.invokeMethod<bool>(
      'revokeAll',
    );
    if (revoked != true && !ignoreErrors) {
      fail('Failed to clear native background migration authorization.');
    }
  } catch (_) {
    if (!ignoreErrors) rethrow;
  }
}

void _pauseApp(WidgetTester tester) {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _resumeApp(WidgetTester tester) {
  if (tester.binding.lifecycleState != AppLifecycleState.paused) return;
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

Future<void> _waitForIdleSync(
  WidgetTester tester,
  ProviderContainer container,
  int targetHeight,
) {
  return pumpUntil(
    tester,
    () {
      final sync = container.read(syncProvider).value;
      return sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= targetHeight;
    },
    description: 'idle mobile wallet sync at $targetHeight',
    timeout: const Duration(minutes: 5),
  );
}

Future<void> _waitForIronwoodSync(
  WidgetTester tester,
  ProviderContainer container,
) {
  return pumpUntil(
    tester,
    () {
      final chain = container.read(chainUpgradeStatusProvider).value;
      final sync = container.read(syncProvider).value;
      return chain?.ironwoodActiveAtTip == true &&
          sync?.isSyncing == false &&
          sync?.isSyncComplete == true &&
          (sync?.scannedHeight ?? 0) >= 500;
    },
    description: 'active Ironwood chain and completed mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
