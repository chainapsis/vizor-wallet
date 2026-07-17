import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _network = 'regtest';
final _fundedAmount = BigInt.from(100020000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'resumes and completes migration in a new Flutter process',
    (tester) async {
      addTearDown(cleanupDesktopRegtestWallet);

      await ironwoodDriverPost(_driverUrl, '/lightwalletd/start');
      final activeChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(activeChain['ironwoodActive'], isTrue);

      final accountUuid = await firstDesktopRegtestAccountUuid();
      final persisted = await desktopRegtestMigrationStatus(accountUuid);
      expect(persisted.activeRunId, isNotNull);
      expect(persisted.phase, 'waiting_denom_confirmations');
      expect(persisted.pendingSplitStageCount, greaterThan(0));

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await unlockDesktopRegtestWallet(tester);
      await tapAppButton(
        tester,
        const ValueKey('home_desktop_ironwood_migration_cta_button'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey(
              'ironwood_migration_status_waiting_denom_confirmations',
            ),
          ),
        ),
        description: 'persisted migration status in the new process',
      );
      final resumed = await desktopRegtestMigrationStatus(accountUuid);
      expect(resumed.activeRunId, persisted.activeRunId);

      await _waitForDenominationMempoolTransaction();

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey(
              'ironwood_migration_status_waiting_migration_confirmations',
            ),
          ),
        ),
        description: 'migration broadcast after process restart',
        timeout: const Duration(minutes: 5),
      );

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_status_complete')),
        ),
        description: 'completed migration after process restart',
        timeout: const Duration(minutes: 5),
      );

      final complete = await desktopRegtestMigrationStatus(accountUuid);
      expect(complete.phase, 'complete');
      expect(complete.confirmedTxCount, complete.totalCount);

      final balance = await rust_sync.getBalance(
        dbPath: await getWalletDbPath(),
        network: _network,
        accountUuid: accountUuid,
      );
      expect(
        balance.ironwood,
        greaterThan(_fundedAmount - BigInt.from(1000000)),
      );
      expect(balance.ironwood, lessThan(_fundedAmount));
      expect(balance.orchard, BigInt.zero);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _waitForDenominationMempoolTransaction() async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
    if ((mempool['size'] as num) > 0) return;
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  throw StateError(
    'Denomination transaction was not rebroadcast after restart.',
  );
}
