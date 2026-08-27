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

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39078',
);
const _recipientAddress = String.fromEnvironment(
  'ZCASH_E2E_SEND_RECIPIENT_ADDRESS',
);
const _network = 'regtest';
final _fundedAmount = BigInt.from(1_100_000);
final _sendAmount = BigInt.from(100_000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'sends Orchard funds before starting the required Ironwood migration',
    (tester) async {
      if (_recipientAddress.isEmpty) {
        fail('ZCASH_E2E_SEND_RECIPIENT_ADDRESS is required.');
      }

      addTearDown(cleanupDesktopRegtestWallet);
      await cleanupDesktopRegtestWallet();

      final initialChain = await ironwoodDriverGet(_driverUrl, '/status');
      expect(initialChain['ironwoodActive'], isFalse);

      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await importDesktopRegtestWallet(tester);
      await pumpUntil(
        tester,
        () =>
            textForKey(
              tester,
              const ValueKey('home_desktop_balance_amount_text'),
            ) ==
            '0.011',
        description: 'pre-Ironwood Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      e2eLog('activating Ironwood without starting migration');
      await ironwoodDriverPost(_driverUrl, '/activate');

      final providerContainer = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final chain = providerContainer
              .read(chainUpgradeStatusProvider)
              .value;
          final sync = providerContainer.read(syncProvider).value;
          final migration = providerContainer
              .read(ironwoodPostMigrationStateProvider)
              .value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              migration?.mode == IronwoodPostMigrationMode.required;
        },
        description: 'required Ironwood migration state',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'Ironwood migration announcement',
      );
      await dismissIronwoodAnnouncement(tester);

      final accountUuid = await firstDesktopRegtestAccountUuid();
      final dbPath = await getWalletDbPath();
      final before = await rust_sync.getBalance(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
      );
      expect(before.orchard, _fundedAmount);
      expect(before.ironwood, BigInt.zero);
      final migrationBefore = await desktopRegtestMigrationStatus(accountUuid);
      expect(migrationBefore.activeRunId, isNull);

      final validation = await rust_sync.validateAddress(
        address: _recipientAddress,
      );
      expect(validation.isValid, isTrue);
      expect(_recipientAddress, startsWith('uregtest1'));
      final expectedFee = await rust_sync.estimateFee(
        dbPath: dbPath,
        network: _network,
        accountUuid: accountUuid,
        toAddress: _recipientAddress,
        amountZatoshi: _sendAmount,
      );

      expect(
        find.byKey(
          const ValueKey('home_desktop_ironwood_migration_cta_button'),
        ),
        findsOneWidget,
      );
      await _sendBeforeMigration(tester);
      await _waitForSentHistory(
        tester,
        dbPath: dbPath,
        accountUuid: accountUuid,
        pending: true,
      );
      final mempool = await ironwoodDriverGet(_driverUrl, '/mempool');
      expect(mempool['size'], greaterThanOrEqualTo(1));
      final migrationAfterBroadcast = await desktopRegtestMigrationStatus(
        accountUuid,
      );
      expect(migrationAfterBroadcast.activeRunId, isNull);

      e2eLog('confirming the pre-migration send');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 11},
      );
      await _waitForConfirmedOrchardChange(
        tester,
        dbPath: dbPath,
        accountUuid: accountUuid,
        expectedOrchard: _fundedAmount - _sendAmount - expectedFee,
      );

      final migrationAfterConfirmation = await desktopRegtestMigrationStatus(
        accountUuid,
      );
      expect(migrationAfterConfirmation.activeRunId, isNull);
      await pumpUntil(
        tester,
        () =>
            providerContainer
                .read(ironwoodPostMigrationStateProvider)
                .value
                ?.mode ==
            IronwoodPostMigrationMode.notNeeded,
        description: 'migration no longer needed after legacy note spend',
        timeout: const Duration(minutes: 3),
      );
      expect(
        find.byKey(
          const ValueKey('home_desktop_ironwood_migration_cta_button'),
        ),
        findsNothing,
      );
      e2eLog(
        'pre-migration Orchard send confirmed; migration is no longer needed',
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _sendBeforeMigration(WidgetTester tester) async {
  await tapAppWidget(tester, const ValueKey('home_desktop_send_button'));
  await enterAppText(
    tester,
    const ValueKey('send_address_field'),
    _recipientAddress,
  );
  await enterAppText(tester, const ValueKey('send_amount_field'), '0.001');
  await tapAppButton(tester, const ValueKey('send_review_button'));
  await tapAppButton(tester, const ValueKey('send_confirm_button'));
  await pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('send_status_completed'))),
    description: 'pre-migration send broadcast',
    timeout: const Duration(minutes: 4),
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
      network: _network,
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
      network: _network,
      accountUuid: accountUuid,
    );
    final history = await rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: _network,
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
