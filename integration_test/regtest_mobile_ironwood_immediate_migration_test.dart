import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

const _fundedAmountZatoshi = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
  defaultValue: 1_095_000,
);
const _fundedNoteCount = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT',
  defaultValue: 1,
);
final _fundedAmount = BigInt.from(_fundedAmountZatoshi);
final _fundedAmountText = ZecAmount.fromZatoshi(
  _fundedAmount,
).compactBalance.amountText;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'immediately migrates $_fundedNoteCount Orchard note(s) on mobile',
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
      await waitForShieldedBalance(
        tester,
        '$_fundedAmountText $mobileE2eTicker',
      );

      final accountUuid = await accountUuidAtOrder(0);
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
      await openMobileImmediateMigrationReview(tester);

      final plan = await rust_sync.getOrchardMigrationImmediatePlan(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(plan, isNotNull);
      final approvedPlan = plan!;
      expect(approvedPlan.totalInputZatoshi, _fundedAmount);
      expect(approvedPlan.plannedTransactionCount, _fundedNoteCount);
      expect(approvedPlan.targetValuesZatoshi, hasLength(_fundedNoteCount));
      expect(
        approvedPlan.keystoneSigningRoundCount,
        (approvedPlan.plannedTransactionCount +
                approvedPlan.signingBatchLimit -
                1) ~/
            approvedPlan.signingBatchLimit,
      );
      expect(
        approvedPlan.totalInputZatoshi - approvedPlan.totalMigratableZatoshi,
        approvedPlan.estimatedTotalFeeZatoshi,
      );

      expect(
        find.textContaining(
          '$_fundedNoteCount visible '
          '${_fundedNoteCount == 1 ? 'transaction' : 'transactions'}',
        ),
        findsOneWidget,
      );
      final startButton = find.descendant(
        of: find.byKey(
          const ValueKey('mobile_ironwood_immediate_start_button'),
        ),
        matching: find.byType(AppButton),
        matchRoot: true,
      );
      expect(tester.widget<AppButton>(startButton).onPressed, isNull);

      await tapWidget(
        tester,
        const ValueKey('mobile_ironwood_fast_acknowledgement'),
      );
      await tapAppButton(
        tester,
        const ValueKey('mobile_ironwood_immediate_start_button'),
        timeout: const Duration(minutes: 5),
      );

      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_ironwood_migration_status_migrating'),
          ),
        ),
        description: 'mobile immediate migration status screen',
        timeout: const Duration(minutes: 10),
      );

      final submitted = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId != null &&
            status.totalCount == _fundedNoteCount &&
            status.broadcastedTxCount + status.confirmedTxCount ==
                _fundedNoteCount,
        description: 'all immediate transactions to be submitted',
        timeout: const Duration(minutes: 10),
      );
      expect(submitted.pendingSplitStageCount, 0);
      expect(submitted.denominationSplitTotalCount, 0);
      expect(submitted.scheduledBroadcasts, hasLength(_fundedNoteCount));
      expect(
        submitted.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
        hasLength(_fundedNoteCount),
      );

      final mempool = await waitForMobileRegtestMempoolSize(
        tester,
        _fundedNoteCount,
        timeout: const Duration(minutes: 5),
      );
      expect((mempool['txids'] as List).toSet(), hasLength(_fundedNoteCount));

      await postDriver('/mine', const {'blocks': 10});
      final complete = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.phase == kIronwoodMigrationCompletePhase &&
            status.confirmedTxCount == _fundedNoteCount &&
            status.activeRunId == null,
        description: 'completed immediate migration',
        timeout: const Duration(minutes: 10),
      );
      expect(complete.activeRunId, isNull);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      final orchardResidual = balance.orchard + balance.uneconomicValue;
      expect(balance.ironwood, approvedPlan.totalMigratableZatoshi);
      expect(orchardResidual, BigInt.zero);
      expect(
        _fundedAmount - balance.ironwood,
        approvedPlan.estimatedTotalFeeZatoshi,
      );

      await waitForHome(tester);
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(
            const ValueKey('mobile_home_ironwood_migration_required_pill'),
          ),
        ),
        description: 'completed immediate migration CTA to disappear',
      );
    },
    timeout: Timeout(Duration(minutes: _fundedNoteCount > 8 ? 40 : 25)),
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
    description: 'idle mobile immediate wallet sync at $targetHeight',
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
    description: 'active Ironwood immediate mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
