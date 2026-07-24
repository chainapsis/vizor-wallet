import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/providers/chain_upgrade_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import 'support/desktop_regtest_flow.dart';

const _driverUrl = String.fromEnvironment(
  'ZCASH_E2E_DRIVER_URL',
  defaultValue: 'http://127.0.0.1:39079',
);
final _fundedAmount = BigInt.from(1100000);
final _sendAmount = BigInt.from(100000);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'isolates migration and spends the resulting Ironwood funds',
    (tester) async {
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
        description: 'funded first-account Orchard balance',
        timeout: const Duration(minutes: 5),
      );

      final firstAccount = (await desktopRegtestAccounts()).single;
      await importAdditionalDesktopRegtestWallet(tester);
      final accounts = await desktopRegtestAccounts();
      expect(accounts, hasLength(2));
      final secondAccount = accounts.singleWhere(
        (account) => account.uuid != firstAccount.uuid,
      );
      final receiverAddress = await _copyActiveShieldedAddress(tester);
      expect(receiverAddress, startsWith('uregtest1'));
      await _openHome(tester);

      await switchDesktopRegtestAccount(tester, firstAccount.uuid);
      final container = ProviderScope.containerOf(
        tester.element(
          find.byKey(const ValueKey('home_desktop_balance_amount_text')),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final sync = container.read(syncProvider).value;
          return sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >=
                  (initialChain['zcashdHeight'] as num);
        },
        description: 'idle pre-Ironwood multi-account sync',
        timeout: const Duration(minutes: 5),
      );

      await ironwoodDriverPost(_driverUrl, '/activate');
      await pumpUntil(
        tester,
        () {
          final chain = container.read(chainUpgradeStatusProvider).value;
          final sync = container.read(syncProvider).value;
          return chain?.ironwoodActiveAtTip == true &&
              sync?.isSyncing == false &&
              sync?.isSyncComplete == true &&
              (sync?.scannedHeight ?? 0) >= 500;
        },
        description: 'active Ironwood multi-account sync',
        timeout: const Duration(minutes: 5),
      );
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(const ValueKey('ironwood_migration_announcement_modal')),
        ),
        description: 'first-account Ironwood announcement',
        timeout: const Duration(minutes: 5),
      );
      await dismissIronwoodAnnouncement(tester);
      final migrationPlan = await rust_sync.getOrchardMigrationPrivatePlan(
        dbPath: await getWalletDbPath(),
        network: 'regtest',
        accountUuid: firstAccount.uuid,
      );
      expect(migrationPlan, isNotNull);
      await openPrivateMigrationReview(tester);
      await startPrivateMigrationFromReview(tester);
      await pumpUntil(
        tester,
        () => tester.any(
          find.byKey(
            const ValueKey(
              'ironwood_migration_status_waiting_denom_confirmations',
            ),
          ),
        ),
        description: 'first-account denomination status',
        timeout: const Duration(minutes: 5),
      );

      final started = await desktopRegtestMigrationStatus(firstAccount.uuid);
      expect(started.activeRunId, isNotNull);

      await switchDesktopRegtestAccount(tester, secondAccount.uuid);
      await pumpUntil(
        tester,
        () => !tester.any(
          find.byKey(
            const ValueKey('home_desktop_ironwood_migration_cta_button'),
          ),
        ),
        description: 'no migration CTA for the unfunded second account',
      );
      final secondStatus = await desktopRegtestMigrationStatus(
        secondAccount.uuid,
      );
      expect(secondStatus.activeRunId, isNull);
      expect(secondStatus.phase, 'no_orchard_funds');
      final firstWhileSecondActive = await desktopRegtestMigrationStatus(
        firstAccount.uuid,
      );
      expect(firstWhileSecondActive.activeRunId, started.activeRunId);

      await switchDesktopRegtestAccount(tester, firstAccount.uuid);
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
        description: 'first-account migration restored after account switch',
      );

      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      await prepareDesktopRegtestMigrationSchedule(tester, firstAccount.uuid);
      await advanceDesktopRegtestMigrationSchedule(
        tester,
        _driverUrl,
        firstAccount.uuid,
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
        description: 'first-account migration completion',
        timeout: const Duration(minutes: 5),
      );

      final complete = await desktopRegtestMigrationStatus(firstAccount.uuid);
      expect(complete.phase, 'complete');
      expect(complete.confirmedTxCount, complete.totalCount);

      final dbPath = await getWalletDbPath();
      final firstBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: 'regtest',
        accountUuid: firstAccount.uuid,
      );
      final orchardResidual =
          firstBalance.orchard + firstBalance.uneconomicValue;
      expect(
        orchardResidual,
        migrationPlan!.orchardChangeZatoshi ?? BigInt.zero,
      );
      expect(firstBalance.ironwood, migrationPlan.totalMigratableZatoshi);
      expect(
        _fundedAmount - orchardResidual - firstBalance.ironwood,
        migrationPlan.estimatedTotalFeeZatoshi,
      );
      final secondBalance = await rust_sync.getBalance(
        dbPath: dbPath,
        network: 'regtest',
        accountUuid: secondAccount.uuid,
      );
      expect(secondBalance.orchard, BigInt.zero);
      expect(secondBalance.ironwood, BigInt.zero);

      await tapAppButton(
        tester,
        const ValueKey('ironwood_migration_status_action_button'),
      );
      await _waitForFundedHomeActions(tester);
      expect(
        find.byKey(const ValueKey('home_desktop_send_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('home_desktop_receive_button')),
        findsOneWidget,
      );

      final postMigrationReceiveAddress = await _copyActiveShieldedAddress(
        tester,
      );
      expect(postMigrationReceiveAddress, startsWith('uregtest1'));
      expect(postMigrationReceiveAddress, isNot(receiverAddress));
      await _openHome(tester);

      e2eLog('sending migrated Ironwood funds through the desktop UI');
      await _sendShielded(tester, receiverAddress, '0.001');
      final mempool = await _waitForMempool(tester, (size) => size == 1);
      final rpcTxid = (mempool['txids'] as List<Object?>).single as String;
      final walletTxid = _reverseTxidBytes(rpcTxid);
      final pendingSent = await _waitForHistoryTransaction(
        tester,
        accountUuid: firstAccount.uuid,
        txKind: 'sent',
        amount: _sendAmount,
        pending: true,
      );
      expect(pendingSent.txidHex, walletTxid);
      expect(pendingSent.displayPool, 'ironwood');
      expect(pendingSent.fee, greaterThan(BigInt.zero));

      await switchDesktopRegtestAccount(tester, secondAccount.uuid);
      final pendingReceive = await _waitForHistoryTransaction(
        tester,
        accountUuid: secondAccount.uuid,
        txKind: 'receiving',
        amount: _sendAmount,
        pending: true,
        txid: walletTxid,
      );
      expect(pendingReceive.displayPool, 'ironwood');
      await _expectActivityRow(
        tester,
        const ValueKey('home_desktop_activity_row_0'),
        title: 'Receiving',
        amount: '+0.001 $kZcashDefaultCurrencyTicker',
        status: 'In progress',
      );

      e2eLog('confirming the post-migration Ironwood send');
      await ironwoodDriverPost(
        _driverUrl,
        '/mine',
        payload: const {'blocks': 10},
      );
      final confirmedReceive = await _waitForHistoryTransaction(
        tester,
        accountUuid: secondAccount.uuid,
        txKind: 'received',
        amount: _sendAmount,
        pending: false,
        txid: walletTxid,
        timeout: const Duration(minutes: 5),
      );
      expect(confirmedReceive.displayPool, 'ironwood');
      final receiverFinalBalance = await _waitForPoolBalance(
        tester,
        accountUuid: secondAccount.uuid,
        orchard: BigInt.zero,
        ironwood: _sendAmount,
      );
      expect(receiverFinalBalance.sapling, BigInt.zero);
      await _expectActivityRow(
        tester,
        const ValueKey('home_desktop_activity_row_0'),
        title: 'Received',
        amount: '+0.001 $kZcashDefaultCurrencyTicker',
        status: 'Completed',
      );

      final receiveDetail = rust_sync.getTransactionDetail(
        dbPath: dbPath,
        network: 'regtest',
        accountUuid: secondAccount.uuid,
        txidHex: walletTxid,
        txKind: 'received',
      );
      expect(
        receiveDetail.outputs,
        contains(
          isA<rust_sync.TransactionDetailOutput>()
              .having((output) => output.pool, 'pool', 'ironwood')
              .having(
                (output) => output.amountZatoshi,
                'amountZatoshi',
                _sendAmount,
              ),
        ),
      );

      await switchDesktopRegtestAccount(tester, firstAccount.uuid);
      final confirmedSent = await _waitForHistoryTransaction(
        tester,
        accountUuid: firstAccount.uuid,
        txKind: 'sent',
        amount: _sendAmount,
        pending: false,
        txid: walletTxid,
      );
      expect(confirmedSent.displayPool, 'ironwood');
      expect(confirmedSent.fee, pendingSent.fee);
      final senderFinalBalance = await _waitForPoolBalance(
        tester,
        accountUuid: firstAccount.uuid,
        orchard: firstBalance.orchard,
        ironwood: firstBalance.ironwood - _sendAmount - confirmedSent.fee,
      );
      expect(senderFinalBalance.sapling, BigInt.zero);
      await _waitForFundedHomeActions(tester);
      await _expectActivityRow(
        tester,
        const ValueKey('home_desktop_activity_row_0'),
        title: 'Sent',
        amount: '-0.001 $kZcashDefaultCurrencyTicker',
        status: 'Completed',
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<String> _copyActiveShieldedAddress(WidgetTester tester) async {
  const regular = ValueKey('home_desktop_receive_button');
  const first = ValueKey('home_desktop_receive_first_button');
  await pumpUntil(
    tester,
    () => tester.any(find.byKey(regular)) || tester.any(find.byKey(first)),
    description: 'home receive action',
  );
  await tapAppWidget(tester, tester.any(find.byKey(regular)) ? regular : first);
  await tapAppWidget(
    tester,
    const ValueKey('receive_copy_shielded_address_button'),
  );
  final clipboard = await Clipboard.getData('text/plain');
  final address = clipboard?.text?.trim() ?? '';
  if (address.isEmpty) fail('Shielded receive address was not copied.');
  return address;
}

Future<void> _openHome(WidgetTester tester) async {
  await tapAppWidget(tester, const ValueKey('sidebar_home_button'));
  await pumpUntil(
    tester,
    () => tester.any(
      find.byKey(const ValueKey('home_desktop_balance_amount_text')),
    ),
    description: 'desktop home after pane navigation',
  );
}

Future<void> _waitForFundedHomeActions(WidgetTester tester) {
  return pumpUntil(
    tester,
    () =>
        tester.any(find.byKey(const ValueKey('home_desktop_send_button'))) &&
        tester.any(find.byKey(const ValueKey('home_desktop_receive_button'))),
    description: 'funded home Send and Receive actions',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> _sendShielded(
  WidgetTester tester,
  String address,
  String amount,
) async {
  await tapAppWidget(tester, const ValueKey('home_desktop_send_button'));
  await enterAppText(tester, const ValueKey('send_address_field'), address);
  await enterAppText(tester, const ValueKey('send_amount_field'), amount);
  await tapAppButton(tester, const ValueKey('send_review_button'));
  await tapAppButton(tester, const ValueKey('send_confirm_button'));
  await pumpUntil(
    tester,
    () => tester.any(find.byKey(const ValueKey('send_status_completed'))),
    description: 'post-migration Ironwood send to complete',
    timeout: const Duration(minutes: 5),
  );
}

Future<Map<String, Object?>> _waitForMempool(
  WidgetTester tester,
  bool Function(int size) condition,
) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  Map<String, Object?>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await ironwoodDriverGet(_driverUrl, '/mempool');
    if (condition(last['size'] as int)) return last;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail('Timed out waiting for post-migration send mempool state. Last: $last');
}

String _reverseTxidBytes(String txid) {
  if (txid.length != 64) fail('Expected a 32-byte txid, got $txid.');
  final bytes = [
    for (var offset = 0; offset < txid.length; offset += 2)
      txid.substring(offset, offset + 2),
  ];
  return bytes.reversed.join();
}

Future<rust_sync.TransactionInfo> _waitForHistoryTransaction(
  WidgetTester tester, {
  required String accountUuid,
  required String txKind,
  required BigInt amount,
  required bool pending,
  String? txid,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(timeout);
  List<rust_sync.TransactionInfo> last = const [];
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      last = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: 'regtest',
        limit: 30,
        accountUuid: accountUuid,
      );
      for (final transaction in last) {
        if (transaction.txKind == txKind &&
            transaction.displayAmount == amount &&
            (transaction.minedHeight == BigInt.zero) == pending &&
            !transaction.expiredUnmined &&
            (txid == null || transaction.txidHex == txid)) {
          return transaction;
        }
      }
      lastError = null;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final history = last
      .map(
        (tx) =>
            '${tx.txidHex}:${tx.txKind}:${tx.displayAmount}:'
            '${tx.displayPool}:height=${tx.minedHeight}',
      )
      .join(', ');
  fail(
    'Timed out waiting for $txKind amount=$amount pending=$pending. '
    'History: $history. Last error: $lastError',
  );
}

Future<rust_sync.WalletBalance> _waitForPoolBalance(
  WidgetTester tester, {
  required String accountUuid,
  required BigInt orchard,
  required BigInt ironwood,
}) async {
  final dbPath = await getWalletDbPath();
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  rust_sync.WalletBalance? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await rust_sync.getBalance(
      dbPath: dbPath,
      network: 'regtest',
      accountUuid: accountUuid,
    );
    if (last.orchard == orchard && last.ironwood == ironwood) return last;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  fail(
    'Timed out waiting for pool balance orchard=$orchard ironwood=$ironwood. '
    'Last: orchard=${last?.orchard}, ironwood=${last?.ironwood}.',
  );
}

Future<void> _expectActivityRow(
  WidgetTester tester,
  Key key, {
  required String title,
  required String amount,
  required String status,
}) {
  return pumpUntil(
    tester,
    () {
      final row = find.byKey(key);
      if (!tester.any(row)) return false;
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>()
          .toSet();
      final titleMatches =
          texts.contains(title) || texts.contains('$title ...');
      const knownStatuses = {'In progress', 'Completed', 'Failed', 'Refunded'};
      final renderedStatuses = texts.where(knownStatuses.contains);
      final statusMatches =
          renderedStatuses.isEmpty || renderedStatuses.contains(status);
      return titleMatches && texts.contains(amount) && statusMatches;
    },
    description: '$key to show $title $amount $status',
    timeout: const Duration(minutes: 2),
  );
}
