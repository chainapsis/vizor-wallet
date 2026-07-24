import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;

import 'support/mobile_regtest_flow.dart';

const _secondMnemonic =
    'return try reason flat civil wolf dwarf announce toddler uphold equip '
    'range neck proof gauge east rifle swim tray twin venue fossil will '
    'version';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    're-imports a deleted active migration account from chain state',
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
      await waitForShieldedBalance(tester, '1.23 $mobileE2eTicker');
      final originalAccountUuid = await accountUuidAtOrder(0);

      await openAddAccountFlow(tester);
      await importWalletViaPaste(
        tester,
        mnemonic: _secondMnemonic,
        birthdayHeight: 1,
        isFirstWallet: false,
      );
      final emptyAccountUuid = await accountUuidAtOrder(1);
      expect(emptyAccountUuid, isNot(originalAccountUuid));

      await switchAccountTo(tester, originalAccountUuid);
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
      final originalPlan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: originalAccountUuid,
      );
      expect(originalPlan, isNotNull);
      expect(originalPlan!.plannedBatchCount, greaterThanOrEqualTo(3));

      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_authorize_start_button'),
        timeout: const Duration(minutes: 5),
      );
      final started = await waitForMobileRegtestMigrationStatus(
        tester,
        originalAccountUuid,
        (status) =>
            status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0,
        description: 'account-removal denomination run',
      );
      final originalRunId = started.activeRunId;
      expect(originalRunId, isNotNull);

      await postDriver('/mine', const {'blocks': 10});
      final scheduled = await waitForMobileRegtestMigrationStatus(
        tester,
        originalAccountUuid,
        (status) =>
            status.activeRunId == originalRunId &&
            status.scheduledBroadcasts.length >= 3,
        description: 'account-removal migration schedule',
        timeout: const Duration(minutes: 10),
      );
      expect(scheduled.totalCount, greaterThanOrEqualTo(3));

      await advanceMobileRegtestMigrationSchedule(
        tester,
        originalAccountUuid,
        submittedTarget: 1,
      );
      await postDriver('/mine', const {'blocks': 1});
      final partiallyConfirmed = await waitForMobileRegtestMigrationStatus(
        tester,
        originalAccountUuid,
        (status) =>
            status.activeRunId == originalRunId &&
            status.confirmedTxCount > 0 &&
            status.scheduledBroadcasts.any(
              (entry) => entry.status == 'scheduled',
            ),
        description: 'confirmed child with remaining scheduled children',
      );
      expect(
        partiallyConfirmed.confirmedTxCount,
        lessThan(scheduled.totalCount),
      );

      final dbPath = await getWalletDbPath();
      final balanceBeforeRemoval = await rust_sync.getBalance(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: originalAccountUuid,
      );
      final expectedRecoveredIronwood =
          balanceBeforeRemoval.ironwood + balanceBeforeRemoval.ironwoodPending;
      final expectedRemainingOrchard =
          balanceBeforeRemoval.orchard +
          balanceBeforeRemoval.orchardPending +
          balanceBeforeRemoval.uneconomicValue;
      expect(expectedRecoveredIronwood, greaterThan(BigInt.zero));
      expect(expectedRemainingOrchard, greaterThan(BigInt.zero));

      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_status_back_home_button'),
      );
      await waitForHome(tester);
      await _removeAccountThroughMobileUi(tester, originalAccountUuid);

      final accountsAfterRemoval = await rust_wallet.listAccounts(
        dbPath: dbPath,
        network: mobileE2eNetwork,
      );
      expect(accountsAfterRemoval.map((account) => account.uuid), [
        emptyAccountUuid,
      ]);
      final removedAccountStatus = await mobileRegtestMigrationStatus(
        originalAccountUuid,
      );
      expect(removedAccountStatus.activeRunId, isNull);
      expect(removedAccountStatus.scheduledBroadcasts, isEmpty);

      // Submitted transactions remain valid after local account deletion.
      await postDriver('/mine', const {'blocks': 10});
      final chainAfterSubmittedTransactions = await getDriver('/status');
      await _waitForIdleSync(
        tester,
        container,
        (chainAfterSubmittedTransactions['zcashdHeight'] as num).toInt(),
      );

      // Rebuild from persisted app state before re-importing. This exercises
      // the on-open account/bootstrap path instead of relying on the notifier
      // instance that performed the deletion.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await pumpUntil(
        tester,
        () =>
            tester.any(find.bySemanticsLabel('Digit 1')) ||
            tester.any(
              find.byKey(const ValueKey('mobile_home_shielded_balance')),
            ),
        description: 'restored wallet bootstrap destination',
      );
      if (tester.any(find.bySemanticsLabel('Digit 1'))) {
        await enterPasscode(tester, mobileE2ePasscode);
      }
      await waitForHome(tester);

      await openAddAccountFlow(tester);
      await importWalletViaPaste(
        tester,
        mnemonic: mobileIronwoodE2eMnemonic,
        birthdayHeight: 1,
        isFirstWallet: false,
      );
      final reimportedAccountUuid = await accountUuidAtOrder(1);
      expect(reimportedAccountUuid, isNot(originalAccountUuid));
      expect(reimportedAccountUuid, isNot(emptyAccountUuid));
      expect(await accountUuidAtOrder(0), emptyAccountUuid);

      final reimportedContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('mobile_home_shielded_balance')),
        ),
      );
      expect(
        reimportedContainer.read(accountProvider).value?.activeAccountUuid,
        reimportedAccountUuid,
      );
      final chainAfterReimport = await getDriver('/status');
      final recoveredBalance = await _waitForRecoveredBalance(
        tester,
        dbPath: dbPath,
        accountUuid: reimportedAccountUuid,
        expectedIronwood: expectedRecoveredIronwood,
        expectedOrchard: expectedRemainingOrchard,
      );
      await _waitForIdleSync(
        tester,
        reimportedContainer,
        (chainAfterReimport['zcashdHeight'] as num).toInt(),
      );

      expect(recoveredBalance.ironwood, expectedRecoveredIronwood);
      expect(
        recoveredBalance.orchard + recoveredBalance.uneconomicValue,
        expectedRemainingOrchard,
      );

      final recoveredStatus = await mobileRegtestMigrationStatus(
        reimportedAccountUuid,
      );
      expect(recoveredStatus.activeRunId, isNull);
      expect(recoveredStatus.phase, kIronwoodMigrationReadyPhase);
      expect(recoveredStatus.targetValuesZatoshi, isEmpty);

      final freshPlan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: reimportedAccountUuid,
      );
      expect(freshPlan, isNotNull);
      expect(freshPlan!.totalInputZatoshi, recoveredBalance.orchard);
      expect(
        freshPlan.totalInputZatoshi -
            freshPlan.totalMigratableZatoshi -
            (freshPlan.orchardChangeZatoshi ?? BigInt.zero),
        freshPlan.estimatedTotalFeeZatoshi,
      );
      expect(
        _sumTargets(freshPlan.targetValuesZatoshi),
        freshPlan.totalMigratableZatoshi,
      );
      expect(
        freshPlan.totalInputZatoshi,
        lessThan(originalPlan.totalInputZatoshi),
      );
      expect(
        freshPlan.totalMigratableZatoshi,
        lessThan(originalPlan.totalMigratableZatoshi),
      );
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}

Future<void> _removeAccountThroughMobileUi(
  WidgetTester tester,
  String accountUuid,
) async {
  await openAccountsSheet(tester);
  await tapUntilVisible(
    tester,
    trigger: find.text('Manage accounts'),
    outcome: find.byKey(ValueKey('mobile_accounts_menu_$accountUuid')),
    description: 'mobile account management screen',
  );
  await tapWidget(tester, ValueKey('mobile_accounts_menu_$accountUuid'));
  await tapWidget(tester, const ValueKey('mobile_account_menu_remove'));
  await pumpUntil(
    tester,
    () => tester.any(
      find.textContaining('migration will no longer continue in Vizor'),
    ),
    description: 'active migration account removal warning',
  );
  await tapAppButton(tester, const ValueKey('mobile_account_remove_confirm'));
  await pumpUntil(
    tester,
    () => !tester.any(find.byKey(ValueKey('mobile_accounts_row_$accountUuid'))),
    description: 'migrating account removal',
    timeout: const Duration(minutes: 2),
  );
  await tapBack(tester);
  await waitForHome(tester);
}

Future<rust_sync.WalletBalance> _waitForRecoveredBalance(
  WidgetTester tester, {
  required String dbPath,
  required String accountUuid,
  required BigInt expectedIronwood,
  required BigInt expectedOrchard,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 8));
  rust_sync.WalletBalance? lastBalance;
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      lastBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      lastError = null;
      final orchard = lastBalance.orchard + lastBalance.uneconomicValue;
      if (lastBalance.ironwood == expectedIronwood &&
          orchard == expectedOrchard) {
        return lastBalance;
      }
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail(
    'Timed out recovering the re-imported account balance. '
    'Last balance: $lastBalance. Last error: $lastError',
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
    description: 'idle mobile account re-import sync at $targetHeight',
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
    description: 'active Ironwood account re-import sync',
    timeout: const Duration(minutes: 5),
  );
}

BigInt _sumTargets(Iterable<BigInt> values) {
  return values.fold(BigInt.zero, (total, value) => total + value);
}
