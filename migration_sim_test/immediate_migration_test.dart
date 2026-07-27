import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../integration_test/support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _blockIntervalMs = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_BLOCK_INTERVAL_MS',
  defaultValue: 3000,
);
const _reviewHoldMs = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_REVIEW_HOLD_MS',
  defaultValue: 5000,
);
const _homeHoldMs = int.fromEnvironment(
  'ZCASH_MIGRATION_SIM_HOME_HOLD_MS',
  defaultValue: 15000,
);
const _fundedZatoshi = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_ZATOSHI',
  defaultValue: 9900020000,
);
const _fundingNoteCount = int.fromEnvironment(
  'ZCASH_E2E_ORCHARD_FUNDING_NOTE_COUNT',
  defaultValue: 20,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'migrates a large many-note wallet immediately in one transaction',
    (tester) async {
      expect(kZcashFastTestnetMigration, isTrue);
      expect(_fundedZatoshi, greaterThanOrEqualTo(1000000000));
      expect(_fundingNoteCount, greaterThanOrEqualTo(10));
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      final accountUuid = await firstDesktopRegtestAccountUuid();
      final dbPath = await getWalletDbPath();
      e2eLog(
        'migration-sim-immediate wallet_db=$dbPath account=$accountUuid '
        'funded=$_fundedZatoshi notes=$_fundingNoteCount',
      );

      final providerContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await _waitForOrchardBalance(
        tester,
        dbPath,
        accountUuid,
        BigInt.from(_fundedZatoshi),
      );

      e2eLog('migration-sim-immediate activating local NU6.3 chain');
      await ironwoodDriverPost(_driverUrl, '/activate');
      await pumpUntil(
        tester,
        () {
          final chain = providerContainer
              .read(chainUpgradeStatusProvider)
              .value;
          final sync = providerContainer.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >=
                  (initialChain['ironwoodActivationHeight'] as num).toInt();
        },
        description: 'local Ironwood activation sync',
        timeout: const Duration(minutes: 5),
      );

      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'migration announcement',
        timeout: const Duration(minutes: 2),
      );
      await dismissIronwoodAnnouncement(tester);
      await openImmediateMigrationReview(tester);

      final plan = await providerContainer.read(
        ironwoodMigrationImmediatePlanProvider.future,
      );
      expect(plan, isNotNull);
      final approvedPlan = plan!;
      expect(approvedPlan.totalInputZatoshi, BigInt.from(_fundedZatoshi));
      expect(approvedPlan.inputNoteCount, _fundingNoteCount);
      expect(approvedPlan.migratedZatoshi, greaterThan(BigInt.zero));
      expect(
        approvedPlan.totalInputZatoshi -
            approvedPlan.feeZatoshi -
            approvedPlan.migratedZatoshi,
        BigInt.zero,
      );
      e2eLog(
        'migration-sim-immediate plan '
        'inputs=${approvedPlan.inputNoteCount} '
        'amount=${approvedPlan.totalInputZatoshi} '
        'fee=${approvedPlan.feeZatoshi} '
        'migrated=${approvedPlan.migratedZatoshi}',
      );

      e2eLog('migration-sim-immediate holding review for ${_reviewHoldMs}ms');
      await Future<void>.delayed(const Duration(milliseconds: _reviewHoldMs));
      await tester.pump();

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_immediate_broadcast_button'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
        description: 'Home after Immediate migration broadcast',
        timeout: const Duration(minutes: 5),
      );

      final mempool = await _waitForMempool(
        tester,
        (size) => size == 1,
        timeout: const Duration(minutes: 5),
      );
      final txids = mempool['txids'] as List<Object?>;
      expect(txids, hasLength(1));
      e2eLog(
        'migration-sim-immediate broadcast txid=${txids.single} '
        'mempool=${mempool['size']}',
      );

      for (var confirmation = 1; confirmation <= 10; confirmation++) {
        await Future<void>.delayed(
          const Duration(milliseconds: _blockIntervalMs),
        );
        await tester.pump();
        await ironwoodDriverPost(
          _driverUrl,
          '/mine',
          payload: const {'blocks': 1},
        );
        final chain = await ironwoodDriverGet(_driverUrl, '/status');
        final targetHeight = (chain['zcashdHeight'] as num).toInt();
        await pumpUntil(
          tester,
          () {
            final sync = providerContainer.read(syncProvider).value;
            return (sync?.scannedHeight ?? 0) >= targetHeight;
          },
          description: 'wallet sync at Immediate confirmation $confirmation',
          timeout: const Duration(minutes: 2),
        );
        e2eLog(
          'migration-sim-immediate confirmation=$confirmation '
          'height=$targetHeight',
        );
      }

      final finalBalance = await _waitForFinalBalance(
        tester,
        dbPath,
        accountUuid,
        approvedPlan,
      );
      expect(finalBalance.orchard + finalBalance.uneconomicValue, BigInt.zero);
      expect(finalBalance.ironwood, approvedPlan.migratedZatoshi);
      expect(
        BigInt.from(_fundedZatoshi) - finalBalance.ironwood,
        approvedPlan.feeZatoshi,
      );

      e2eLog(
        'migration-sim-immediate IMMEDIATE_MIGRATION_COMPLETE '
        'txid=${txids.single} ironwood=${finalBalance.ironwood} '
        'fee=${approvedPlan.feeZatoshi}',
      );

      await tapAppWidget(tester, const ValueKey('sidebar_activity_button'));
      await pumpUntil(
        tester,
        () =>
            tester.any(find.text('Migrated to Ironwood')) &&
            tester.any(find.text('Orchard → Ironwood')),
        description: 'Immediate migration entry in Activity',
        timeout: const Duration(minutes: 2),
      );
      e2eLog(
        'migration-sim-immediate ACTIVITY_MIGRATION_VISIBLE '
        'title="Migrated to Ironwood" pool="Orchard → Ironwood"',
      );
      e2eLog('migration-sim-immediate holding Activity for ${_homeHoldMs}ms');
      await Future<void>.delayed(const Duration(milliseconds: _homeHoldMs));
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _waitForOrchardBalance(
  WidgetTester tester,
  String dbPath,
  String accountUuid,
  BigInt expected,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  rust_sync.WalletBalance? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await rust_sync.getBalance(
      dbPath: dbPath,
      network: 'regtest',
      accountUuid: accountUuid,
    );
    if (last.orchard == expected) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Expected Orchard balance $expected, last balance: ${last?.orchard}.');
}

Future<Map<String, Object?>> _waitForMempool(
  WidgetTester tester,
  bool Function(int size) condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await ironwoodDriverGet(_driverUrl, '/mempool');
    if (condition((last['size'] as num).toInt())) return last;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for Immediate migration mempool state. Last: $last');
}

Future<rust_sync.WalletBalance> _waitForFinalBalance(
  WidgetTester tester,
  String dbPath,
  String accountUuid,
  rust_sync.OrchardMigrationImmediatePlan plan,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  rust_sync.WalletBalance? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await rust_sync.getBalance(
      dbPath: dbPath,
      network: 'regtest',
      accountUuid: accountUuid,
    );
    if (last.ironwood == plan.migratedZatoshi &&
        last.orchard + last.uneconomicValue == BigInt.zero) {
      return last;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for Immediate migration balance. Last: $last');
}
