import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/formatting/zec_amount.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_announcement_provider.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/mobile_regtest_flow.dart';

int get _fundedAmountZatoshi => mobileE2eFiveHundredNotes
    ? 500_000_000
    : const int.fromEnvironment(
        'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
        defaultValue: 1_000_020_000,
      );
int get _fundedNoteCount => mobileE2eFiveHundredNotes
    ? 500
    : const int.fromEnvironment(
        'ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT',
        defaultValue: 20,
      );
int get _expectedSplitStageCount => mobileE2eFiveHundredNotes
    ? 44
    : const int.fromEnvironment(
        'ZCASH_E2E_EXPECTED_SPLIT_STAGE_COUNT',
        defaultValue: 4,
      );
int get _expectedMigrationBatchCount => mobileE2eFiveHundredNotes
    ? 7
    : const int.fromEnvironment(
        'ZCASH_E2E_EXPECTED_MIGRATION_BATCH_COUNT',
        defaultValue: 9,
      );
final _fundedAmount = BigInt.from(_fundedAmountZatoshi);
final _fundedAmountText = ZecAmount.fromZatoshi(
  _fundedAmount,
).compactBalance.amountText;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets('migrates $_fundedNoteCount Orchard notes on mobile', (
    tester,
  ) async {
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
    await waitForShieldedBalance(tester, '$_fundedAmountText $mobileE2eTicker');

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
    await openMobilePrivateMigrationOptions(tester);

    final plan = await rust_sync.getOrchardMigrationPrivatePlan(
      dbPath: await getWalletDbPath(),
      network: mobileE2eNetwork,
      accountUuid: accountUuid,
      spacePreparationBroadcasts: false,
    );
    expect(plan, isNotNull);
    final approvedPlan = plan!;
    expect(approvedPlan.totalInputZatoshi, _fundedAmount);
    expect(approvedPlan.denominationSplitStageCount, _expectedSplitStageCount);
    expect(approvedPlan.plannedBatchCount, _expectedMigrationBatchCount);
    expect(
      approvedPlan.targetValuesZatoshi,
      hasLength(_expectedMigrationBatchCount),
    );
    final preparationLayers = mobileManyNotePreparationLayers(
      _fundedNoteCount,
      _fundedAmountZatoshi,
    );
    expect(approvedPlan.denominationSplitLayerCount, preparationLayers.length);
    expect(preparationLayers.reduce((a, b) => a + b), _expectedSplitStageCount);

    await startMobilePrivateMigration(tester);
    final started = await waitForMobileRegtestMigrationStatus(
      tester,
      accountUuid,
      (status) =>
          status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
          status.denominationSplitTotalCount == _expectedSplitStageCount &&
          status.denominationSplitCompletedCount == 0 &&
          status.pendingSplitStageCount == _expectedSplitStageCount,
      description: 'first mobile many-note split stage',
    );
    final runId = started.activeRunId;
    expect(runId, isNotNull);
    validateMobilePreparationTopology(
      started.preparationTransactions ?? const [],
      preparationLayers,
      approvedPlan.denominationSplitFeeZatoshi,
    );

    var completedStageCount = 0;
    final observedPreparationTxids = <String>{};
    for (var layer = 0; layer < preparationLayers.length; layer++) {
      final mempool = await waitForMobileRegtestMempoolSize(
        tester,
        preparationLayers[layer],
      );
      final txids = validateMobilePreparationMempool(
        mempool,
        preparationLayers[layer],
        observedPreparationTxids,
      );
      observedPreparationTxids.addAll(txids);
      final beforeMine = await getDriver('/status');
      final beforeHeight = (beforeMine['zcashdHeight'] as num).toInt();
      // Existing RPC helper selects the managed native boundary or standalone
      // node RPC and rejects RPC errors before returning exact generated hashes.
      final hashes = (await zcashdRpc<List<Object?>>('generate', const [
        10,
      ])).cast<String>();
      expect(hashes, hasLength(10));
      expect(hashes.toSet(), hasLength(10));
      expect(
        hashes.every((hash) => RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)),
        isTrue,
      );
      completedStageCount += preparationLayers[layer];
      final confirmed = await waitForMobileRegtestMigrationStatus(
        tester,
        accountUuid,
        (status) =>
            status.activeRunId == runId &&
            status.denominationSplitCompletedCount == completedStageCount,
        description:
            'mobile many-note preparation round ${layer + 1} '
            '$completedStageCount/$_expectedSplitStageCount',
        timeout: const Duration(minutes: 10),
      );
      validateMobilePreparationTopology(
        confirmed.preparationTransactions ?? const [],
        preparationLayers,
        approvedPlan.denominationSplitFeeZatoshi,
      );
      validateMobilePreparationConfirmedLayer(
        confirmed.preparationTransactions!,
        layer + 1,
        preparationLayers[layer],
        beforeHeight,
      );
      for (final txid in txids) {
        final proof = await zcashdRpc<Map<String, Object?>>(
          'getrawtransaction',
          [txid, 1],
        );
        validateMobilePreparationTransactionProof(proof, txid, hashes);
      }
    }
    expect(observedPreparationTxids, hasLength(_expectedSplitStageCount));

    final scheduled = await prepareMobilePrivateMigrationSchedule(
      tester,
      accountUuid,
      (status) =>
          status.activeRunId == runId &&
          status.denominationSplitCompletedCount == _expectedSplitStageCount &&
          status.scheduledBroadcasts.length == _expectedMigrationBatchCount,
      description: 'mobile many-note migration schedule',
      timeout: const Duration(minutes: 10),
    );
    expect(scheduled.targetValuesZatoshi, approvedPlan.targetValuesZatoshi);
    expect(
      scheduled.scheduledBroadcasts.map((entry) => entry.txidHex).toSet(),
      hasLength(_expectedMigrationBatchCount),
    );

    final submitted = await advanceMobileRegtestMigrationSchedule(
      tester,
      accountUuid,
      timeout: const Duration(minutes: 10),
    );
    expect(submitted.activeRunId, runId);
    expect(
      submitted.broadcastedTxCount + submitted.confirmedTxCount,
      submitted.totalCount,
    );

    await postDriver('/mine', const {'blocks': 10});
    final complete = await waitForMobileRegtestMigrationStatus(
      tester,
      accountUuid,
      (status) =>
          status.phase == kIronwoodMigrationCompletePhase &&
          status.activeRunId == null,
      description: 'completed mobile many-note migration',
    );
    expect(complete.activeRunId, isNull);

    final balance = await rust_sync.getBalance(
      dbPath: await getWalletDbPath(),
      network: mobileE2eNetwork,
      accountUuid: accountUuid,
    );
    final orchardResidual = balance.orchard + balance.uneconomicValue;
    expect(balance.ironwood, approvedPlan.totalMigratableZatoshi);
    expect(orchardResidual, approvedPlan.orchardChangeZatoshi ?? BigInt.zero);
    expect(
      _fundedAmount - balance.ironwood - orchardResidual,
      approvedPlan.estimatedTotalFeeZatoshi,
    );
    await finishMobilePrivateMigrationForHome(tester);
    markMobileE2eAssertionsCompleted();
  }, timeout: Timeout(Duration(minutes: _fundedNoteCount >= 100 ? 90 : 30)));
}

// Fixed funding vectors, independently checked by the actual Rust planner in
// isolated_ios_many_note_fixture_plans_preserve_layers_and_value. These are
// not cardinalities inferred from the wallet/status response being tested.
List<int> mobileManyNotePreparationLayers(int notes, int fundedZatoshi) {
  if (notes == 20 && fundedZatoshi == 1000020000) return const [2, 1, 1];
  if (notes == 500 && fundedZatoshi == 500000000) {
    return const [35, 5, 2, 1, 1];
  }
  throw StateError('No independently verified preparation layers for funding');
}

void _requirePreparation(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void validateMobilePreparationTopology(
  List<rust_sync.MigrationPreparationTransactionStatus> stages,
  List<int> layers,
  BigInt totalFee,
) {
  final expectedRounds = [
    for (var layer = 0; layer < layers.length; layer++)
      for (var stage = 0; stage < layers[layer]; stage++) layer + 1,
  ];
  _requirePreparation(
    stages.length == expectedRounds.length,
    'Stage count mismatch',
  );
  final byIndex = {for (final stage in stages) stage.stageIndex: stage};
  _requirePreparation(byIndex.length == stages.length, 'Duplicate stage index');
  // Public plan fee is a total; stage status fee is per transaction. The exact
  // independently probed Regtest policy charges 80,000 for each padded stage.
  final stageFee = BigInt.from(80000);
  for (var index = 0; index < expectedRounds.length; index++) {
    final stage = byIndex[index];
    _requirePreparation(stage != null, 'Missing stage $index');
    _requirePreparation(
      stage!.round == expectedRounds[index],
      'Wrong round for stage $index',
    );
    _requirePreparation(
      stage.feeZatoshi == stageFee,
      'Wrong fee for stage $index',
    );
    _requirePreparation(
      stage.confirmationTarget == 3,
      'Wrong confirmation target for stage $index',
    );
  }
  _requirePreparation(
    stages.fold(BigInt.zero, (total, stage) => total + stage.feeZatoshi) ==
        totalFee,
    'Wrong total preparation fee',
  );
}

List<String> validateMobilePreparationMempool(
  Map<String, Object?> mempool,
  int expected,
  Set<String> seen,
) {
  final raw = mempool['txids'];
  _requirePreparation(
    mempool['size'] == expected && raw is List,
    'Wrong mempool cardinality',
  );
  final txids = (raw as List).cast<String>();
  _requirePreparation(
    txids.length == expected && txids.toSet().length == expected,
    'Missing or duplicate preparation txids',
  );
  _requirePreparation(
    txids.every(
      (txid) =>
          RegExp(r'^[0-9a-f]{64}$').hasMatch(txid) && !seen.contains(txid),
    ),
    'Invalid or repeated preparation txid',
  );
  return txids;
}

void validateMobilePreparationConfirmedLayer(
  List<rust_sync.MigrationPreparationTransactionStatus> stages,
  int round,
  int expected,
  int beforeHeight,
) {
  final layer = stages.where((stage) => stage.round == round).toList();
  _requirePreparation(layer.length == expected, 'Wrong confirmed layer size');
  for (final stage in layer) {
    _requirePreparation(
      stage.state == rust_sync.MigrationPreparationTransactionState.completed,
      'Stage ${stage.stageIndex} not complete',
    );
    _requirePreparation(
      // Pinned SDK trusted depth is three and its displayed count is capped
      // there. Actual node depth is independently proved >= ten below.
      stage.confirmationTarget == 3 && stage.confirmationCount == 3,
      'Stage ${stage.stageIndex} lacks trusted confirmations',
    );
    _requirePreparation(
      stage.minedHeight != null &&
          stage.minedHeight! > beforeHeight &&
          stage.minedHeight! <= beforeHeight + 10,
      'Stage ${stage.stageIndex} lacks inclusion in the mined interval',
    );
  }
}

void validateMobilePreparationTransactionProof(
  Map<String, Object?> proof,
  String txid,
  List<String> minedHashes,
) {
  _requirePreparation(
    proof['txid'] == txid,
    'Transaction proof identity mismatch',
  );
  _requirePreparation(
    proof['confirmations'] is num && (proof['confirmations'] as num) >= 10,
    'Transaction lacks trusted confirmations',
  );
  _requirePreparation(
    proof['blockhash'] is String && minedHashes.contains(proof['blockhash']),
    'Transaction absent from exact generated blocks',
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
    description: 'idle mobile many-note sync at $targetHeight',
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
    description: 'active Ironwood many-note mobile sync',
    timeout: const Duration(minutes: 5),
  );
}
