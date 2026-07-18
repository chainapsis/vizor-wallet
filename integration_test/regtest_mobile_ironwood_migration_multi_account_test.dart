import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

const _secondMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';
final _fundedAmount = BigInt.from(1_100_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'keeps a mobile migration isolated to its funded account',
    (tester) async {
      tolerateRenderOverflows();
      addTearDown(cleanupE2eWalletState);
      await cleanupE2eWalletState();

      final initialChain = await getDriver('/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: true,
      );
      await waitForShieldedBalance(tester, '0.011 $mobileE2eTicker');
      final firstAccountUuid = await accountUuidAtOrder(0);

      await openAddAccountFlow(tester);
      await importWalletViaPaste(
        tester,
        mnemonic: _secondMnemonic,
        birthdayHeight: 1,
        isFirstWallet: false,
      );
      final secondAccountUuid = await accountUuidAtOrder(1);
      expect(secondAccountUuid, isNot(firstAccountUuid));

      await switchAccountTo(tester, firstAccountUuid);
      await waitForShieldedBalance(tester, '0.011 $mobileE2eTicker');
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
      final plan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: firstAccountUuid,
      );
      expect(plan, isNotNull);

      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        firstAccountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'funded-account mobile migration run',
      );
      final runId = started.activeRunId;
      expect(runId, isNotNull);

      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_status_back_home_button'),
      );
      await waitForHome(tester);
      await switchAccountTo(tester, secondAccountUuid);
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(
            const ValueKey('mobile_home_ironwood_migration_required_pill'),
          ),
        ),
        description: 'no migration CTA for unfunded mobile account',
      );
      final secondStatus = await mobileRegtestMigrationStatus(
        secondAccountUuid,
      );
      expect(secondStatus.activeRunId, isNull);
      expect(secondStatus.phase, kIronwoodMigrationNoOrchardFundsPhase);
      expect(
        (await mobileRegtestMigrationStatus(firstAccountUuid)).activeRunId,
        runId,
      );

      await switchAccountTo(tester, firstAccountUuid);
      await tapWidget(
        tester,
        const ValueKey('mobile_home_ironwood_migration_required_pill'),
        timeout: const Duration(minutes: 2),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_ironwood_migration_status_preparing'),
          ),
        ),
        description: 'funded-account migration restored after account switch',
      );

      await waitForMobileRegtestMempoolSize(tester, 1);
      await postDriver('/mine', const {'blocks': 10});
      await waitForMobileRegtestMigrationStatus(
        tester,
        firstAccountUuid,
        (status) => status.scheduledBroadcasts.isNotEmpty,
        description: 'funded-account persisted migration schedule',
        timeout: const Duration(minutes: 10),
      );
      await advanceMobileRegtestMigrationSchedule(tester, firstAccountUuid);
      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        firstAccountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.activeRunId == null,
        description: 'funded-account migration completion',
      );
      expect(complete.activeRunId, isNull);

      final dbPath = await getWalletDbPath();
      final firstBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: firstAccountUuid,
      );
      final firstOrchardResidual =
          firstBalance.orchard + firstBalance.uneconomicValue;
      expect(firstBalance.ironwood, plan!.totalMigratableZatoshi);
      expect(firstOrchardResidual, plan.orchardChangeZatoshi ?? BigInt.zero);
      expect(
        _fundedAmount - firstBalance.ironwood - firstOrchardResidual,
        plan.estimatedTotalFeeZatoshi,
      );

      final secondBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: secondAccountUuid,
      );
      expect(secondBalance.orchard, BigInt.zero);
      expect(secondBalance.ironwood, BigInt.zero);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
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
    description: 'idle mobile multi-account sync at $targetHeight',
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
    description: 'active Ironwood multi-account mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
