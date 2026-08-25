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

const _recipientAddress = String.fromEnvironment(
  'ZCASH_E2E_SEND_RECIPIENT_ADDRESS',
);
final _fundedAmount = BigInt.from(1_095_000);
final _sendAmount = BigInt.from(100_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'sends Orchard funds on iOS before starting the required migration',
    (tester) async {
      tolerateRenderOverflows();
      if (_recipientAddress.isEmpty) {
        fail('ZCASH_E2E_SEND_RECIPIENT_ADDRESS is required.');
      }

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
      await waitForShieldedBalance(tester, '0.01095 $mobileE2eTicker');

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

      logE2e('activating Ironwood without starting migration');
      await postDriver('/activate', const {});
      await pumpUntil(
        tester,
        () {
          final chain = container.read(chainUpgradeStatusProvider).value;
          final sync = container.read(syncProvider).value;
          final migration = container
              .read(ironwoodPostMigrationStateProvider)
              .value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              migration?.mode == IronwoodPostMigrationMode.required;
        },
        description: 'required mobile Ironwood migration state',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('mobile_ironwood_announcement_sheet')),
        ),
        description: 'mobile Ironwood migration announcement',
      );
      await tapWidget(
        tester,
        const ValueKey('mobile_ironwood_announcement_close_button'),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey('mobile_home_ironwood_migration_required_pill'),
          ),
        ),
        description: 'mobile Ironwood migration CTA',
      );

      final accountUuid = await accountUuidAtOrder(0);
      final dbPath = await getWalletDbPath();
      final before = await rust_sync.getBalance(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
      );
      expect(before.orchard, _fundedAmount);
      expect(before.ironwood, BigInt.zero);
      expect(
        (await mobileRegtestMigrationStatus(accountUuid)).activeRunId,
        isNull,
      );

      final validation = await rust_sync.validateAddress(
        address: _recipientAddress,
      );
      expect(validation.isValid, isTrue);
      expect(_recipientAddress, startsWith('uregtest1'));
      final expectedFee = await rust_sync.estimateFee(
        dbPath: dbPath,
        network: mobileE2eNetwork,
        accountUuid: accountUuid,
        toAddress: _recipientAddress,
        amountZatoshi: _sendAmount,
      );

      await sendViaWizard(
        tester,
        address: _recipientAddress,
        amountDigits: '0.001',
      );
      await _waitForSentHistory(
        tester,
        dbPath: dbPath,
        accountUuid: accountUuid,
        pending: true,
      );
      final mempool = await getDriver('/mempool');
      expect(mempool['size'], greaterThanOrEqualTo(1));
      expect(
        (await mobileRegtestMigrationStatus(accountUuid)).activeRunId,
        isNull,
      );

      logE2e('confirming the iOS pre-migration send');
      await postDriver('/mine', const {'blocks': 11});
      await _waitForConfirmedOrchardChange(
        tester,
        dbPath: dbPath,
        accountUuid: accountUuid,
        expectedOrchard: _fundedAmount - _sendAmount - expectedFee,
      );

      expect(
        (await mobileRegtestMigrationStatus(accountUuid)).activeRunId,
        isNull,
      );
      await pumpUntil(
        tester,
        () =>
            container.read(ironwoodPostMigrationStateProvider).value?.mode ==
            IronwoodPostMigrationMode.notNeeded,
        description: 'mobile migration no longer needed after legacy spend',
        timeout: const Duration(minutes: 3),
      );
      expect(
        find.byKey(
          const ValueKey('mobile_home_ironwood_migration_required_pill'),
        ),
        findsNothing,
      );
      logE2e(
        'iOS pre-migration Orchard send confirmed; migration is not needed',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
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
    description: 'idle mobile wallet sync at $targetHeight',
    timeout: const Duration(minutes: 5),
  );
}

Future<void> _waitForSentHistory(
  WidgetTester tester, {
  required String dbPath,
  required String accountUuid,
  required bool pending,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  var lastHistory = '<not read>';
  while (DateTime.now().isBefore(deadline)) {
    final history = await rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: mobileE2eNetwork,
      limit: 20,
      accountUuid: accountUuid,
    );
    lastHistory = history
        .map(
          (tx) =>
              '${tx.txidHex}:${tx.txKind}:${tx.displayAmount}:${tx.minedHeight}',
        )
        .join(', ');
    if (history.any(
      (tx) =>
          tx.txKind == 'sent' &&
          tx.displayAmount == _sendAmount &&
          (tx.minedHeight == BigInt.zero) == pending &&
          !tx.expiredUnmined,
    )) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail(
    'Timed out waiting for pending=$pending sent history. Last: $lastHistory',
  );
}

Future<void> _waitForConfirmedOrchardChange(
  WidgetTester tester, {
  required String dbPath,
  required String accountUuid,
  required BigInt expectedOrchard,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  rust_sync.WalletBalance? lastBalance;
  while (DateTime.now().isBefore(deadline)) {
    lastBalance = await rust_sync.getBalance(
      dbPath: dbPath,
      network: mobileE2eNetwork,
      accountUuid: accountUuid,
    );
    final history = await rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: mobileE2eNetwork,
      limit: 20,
      accountUuid: accountUuid,
    );
    final confirmed = history.any(
      (tx) =>
          tx.txKind == 'sent' &&
          tx.displayAmount == _sendAmount &&
          tx.minedHeight > BigInt.zero &&
          !tx.expiredUnmined,
    );
    if (confirmed &&
        lastBalance.orchard == expectedOrchard &&
        lastBalance.ironwood == BigInt.zero) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail(
    'Timed out waiting for confirmed Orchard change. '
    'Expected Orchard $expectedOrchard, last balance: $lastBalance',
  );
}
