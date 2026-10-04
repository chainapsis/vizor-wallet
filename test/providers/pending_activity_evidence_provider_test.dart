import 'dart:async';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/activity_eta_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/pending_activity_evidence_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';

import '../fakes/fake_sync_notifier.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

class _Accounts extends AccountNotifier {
  @override
  Future<AccountState> build() async =>
      const AccountState(activeAccountUuid: 'a');
}

void main() {
  final started = DateTime.utc(2026, 10, 6);

  test('resume and repeated focus retain original freshness deadline', () {
    var now = started;
    final container = ProviderContainer(
      overrides: [activityEtaClockProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);
    final evidence = container.read(pendingActivityEvidenceProvider.notifier);
    String? label() => container
        .read(pendingActivityEvidenceProvider)
        .labelFor('a', 'tx', 100);
    evidence.observe(accountUuid: 'a', txids: ['tx']);
    evidence.networkChecked(100);
    evidence.setForeground(false);
    now = started.add(const Duration(seconds: 12));
    evidence.setForeground(true);
    expect(label(), 'Est. 1–3 min');
    now = started.add(const Duration(seconds: 29));
    evidence.setForeground(true);
    expect(label(), 'Est. 1–3 min');
    now = started.add(const Duration(seconds: 30));
    evidence.setForeground(true);
    expect(label(), isNull);
    expect(
      container.read(pendingActivityEvidenceProvider).networkCheckedAt,
      started,
    );
    now = started.add(const Duration(minutes: 2));
    evidence.setForeground(false);
    evidence.setForeground(true);
    expect(label(), isNull);
  });

  test(
    'background checks need explicit desktop permission and retain hidden state',
    () {
      var now = started;
      final container = ProviderContainer(
        overrides: [activityEtaClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        pendingActivityEvidenceProvider.notifier,
      );
      controller.observe(accountUuid: 'a', txids: ['tx']);
      controller.networkChecked(100);
      controller.setForeground(false);
      now = started.add(const Duration(minutes: 1));
      controller.networkChecked(101);
      expect(
        container.read(pendingActivityEvidenceProvider).networkCheckedAt,
        started,
      );
      controller.networkChecked(100, allowBackground: true);
      expect(
        container.read(pendingActivityEvidenceProvider).foreground,
        isFalse,
      );
      expect(
        container
            .read(pendingActivityEvidenceProvider)
            .labelFor('a', 'tx', 100),
        isNull,
      );
      controller.setForeground(true);
      expect(
        container
            .read(pendingActivityEvidenceProvider)
            .labelFor('a', 'tx', 100),
        'Est. 1–3 min',
      );
    },
  );

  test(
    'only observed connectivity failures use the connection fallback',
    () async {
      final sync = FakeSyncNotifier(SyncState());
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => sync)],
      );
      addTearDown(container.dispose);
      await container.read(syncProvider.future);
      final evidence = container.read(pendingActivityEvidenceProvider.notifier);
      expect(
        container.read(activityPendingFallbackLabelProvider),
        'Checking status',
      );
      evidence.invalidateNetwork(connectionFailed: true);
      evidence.setForeground(false);
      evidence.setForeground(true);
      expect(
        container.read(activityPendingFallbackLabelProvider),
        'Waiting for connection',
      );
      evidence.networkChecked(100);
      expect(
        container.read(activityPendingFallbackLabelProvider),
        'Checking status',
      );
      for (final message in [
        'database is locked',
        'private status coverage incomplete',
        'chain continuity broken',
        'invalid url',
      ]) {
        sync.emit(SyncState(failure: classifySyncFailure(message)));
        expect(
          container.read(activityPendingFallbackLabelProvider),
          'Checking status',
        );
      }
      sync.emit(
        SyncState(failure: classifySyncFailure('network connection refused')),
      );
      expect(
        container.read(activityPendingFallbackLabelProvider),
        'Waiting for connection',
      );
    },
  );

  test(
    'estimate requires propagation, a fresh tip, and scanning through it',
    () {
      PendingActivityEvidence evidence({
        DateTime? checked,
        int? tip = 100,
        DateTime? observed,
        DateTime? now,
        bool foreground = true,
      }) => PendingActivityEvidence(
        now: now ?? started,
        networkCheckedAt: checked,
        checkedTip: tip,
        foreground: foreground,
        observedAt: observed == null ? const {} : {('a', 'tx'): observed},
      );
      expect(evidence(checked: started).labelFor('a', 'tx', 100), isNull);
      expect(evidence(observed: started).labelFor('a', 'tx', 100), isNull);
      final ready = evidence(checked: started, observed: started);
      expect(ready.labelFor('a', 'tx', 100), 'Est. 1–3 min');
      expect(ready.labelFor('other-account', 'tx', 100), isNull);
      expect(ready.labelFor('a', 'other-tx', 100), isNull);
      expect(ready.labelFor('a', 'tx', 99), isNull);
      expect(
        evidence(
          checked: started,
          observed: started,
          now: started.add(kActivityEtaFreshness),
        ).labelFor('a', 'tx', 100),
        isNull,
      );
      expect(
        evidence(
          checked: started,
          observed: started,
          foreground: false,
        ).labelFor('a', 'tx', 100),
        isNull,
      );
      expect(
        evidence(
          checked: started,
          observed: started,
          now: started.subtract(const Duration(seconds: 1)),
        ).labelFor('a', 'tx', 100),
        isNull,
      );
    },
  );

  testWidgets(
    'shared clock expires ETA, duplicate observations preserve wait, and short lifecycle transitions preserve it',
    (tester) async {
      var now = started;
      final container = ProviderContainer(
        overrides: [activityEtaClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        pendingActivityEvidenceProvider.notifier,
      );
      String? label() => container
          .read(pendingActivityEvidenceProvider)
          .labelFor('a', 'tx', 100);
      controller.observe(accountUuid: 'a', txids: ['tx']);
      controller.networkChecked(100);
      expect(label(), 'Est. 1–3 min');
      now = started.add(kActivityEtaFreshness);
      await tester.pump(const Duration(seconds: 30));
      expect(label(), isNull);
      now = started.add(kActivityLongWait);
      controller.observe(accountUuid: 'a', txids: ['tx']);
      controller.networkChecked(100);
      expect(label(), 'Taking longer');
      controller.setForeground(false);
      expect(label(), isNull);
      controller.setForeground(true);
      expect(label(), 'Taking longer');
      controller.networkChecked(100);
      expect(label(), 'Taking longer');
      controller.invalidateNetwork();
      expect(label(), isNull);
      controller.networkChecked(100);
      controller.clear();
      controller.networkChecked(100);
      expect(label(), isNull);
    },
  );

  test(
    'TEX range and long wait use 8 minutes before the funding step confirms',
    () {
      PendingActivityEvidence at(Duration elapsed) => PendingActivityEvidence(
        now: started.add(elapsed),
        networkCheckedAt: started.add(elapsed),
        checkedTip: 100,
        observedAt: {('a', 'tx'): started},
      );
      expect(
        at(const Duration(minutes: 5)).labelFor('a', 'tx', 100),
        'Taking longer',
      );
      expect(
        at(
          const Duration(minutes: 5),
        ).labelFor('a', 'tx', 100, waitingForFunding: true),
        'Est. 2–6 min',
      );
      expect(
        at(
          const Duration(minutes: 8),
        ).labelFor('a', 'tx', 100, waitingForFunding: true),
        'Taking longer',
      );
    },
  );

  testWidgets(
    'opposite txid byte orders share evidence and cannot restart its clock',
    (tester) async {
      var now = started;
      final container = ProviderContainer(
        overrides: [activityEtaClockProvider.overrideWithValue(() => now)],
      );
      addTearDown(container.dispose);
      final prefix = '01' * 31;
      final first = '${prefix}02';
      final reverse = '02$prefix';
      final controller = container.read(
        pendingActivityEvidenceProvider.notifier,
      );
      controller.observe(accountUuid: 'a', txids: [first]);
      now = started.add(const Duration(minutes: 5));
      controller.observe(accountUuid: 'a', txids: [reverse]);
      controller.networkChecked(100);
      final evidence = container.read(pendingActivityEvidenceProvider);
      expect(evidence.observedAt, hasLength(1));
      expect(evidence.labelFor('a', reverse, 100), 'Taking longer');
      controller.clear();
    },
  );

  test(
    'TEX label follows the hidden funding state and blocks expired dependencies',
    () {
      rust_sync.TransactionInfo tx({BigInt? height, bool? expired = false}) =>
          _tx(
            'child',
            parent: 'parent',
            parentHeight: height,
            parentExpired: expired,
          );
      const labels = {'child': 'Est. 1–3 min', 'funding:child': 'Est. 2–6 min'};
      expect(
        activityEtaLabelFor(
          transaction: tx(height: BigInt.zero),
          labels: labels,
        ),
        'Est. 2–6 min',
      );
      expect(
        activityEtaLabelFor(
          transaction: tx(height: BigInt.one),
          labels: labels,
        ),
        'Est. 1–3 min',
      );
      expect(
        activityEtaLabelFor(
          transaction: tx(height: BigInt.zero, expired: true),
          labels: labels,
        ),
        isNull,
      );
      expect(activityEtaLabelFor(transaction: tx(), labels: labels), isNull);
    },
  );

  test('Gift Card ETA covers every leg rather than the representative row', () {
    String? label(
      List<rust_sync.TransactionInfo> txs,
      Map<String, String> labels,
    ) => giftCardClaimEtaLabel(
      ids: {'first', 'second'},
      transactions: txs,
      scannedHeight: 100,
      labels: labels,
    );
    expect(
      label([_tx('first', mined: BigInt.from(99))], {'second': 'Est. 1–3 min'}),
      'Est. 1–3 min',
    );
    expect(label([_tx('first', mined: BigInt.from(99))], {}), isNull);
    expect(
      label([], {'first': 'Est. 1–3 min', 'second': 'Taking longer'}),
      'Taking longer',
    );
    expect(
      label(
        [_tx('first', expired: true)],
        {'first': 'Est. 1–3 min', 'second': 'Est. 1–3 min'},
      ),
      isNull,
    );
    expect(
      label([
        _tx('first', mined: BigInt.from(99)),
        _tx('second', mined: BigInt.from(99)),
      ], {}),
      isNull,
    );
    expect(
      label(
        [_tx('first', mined: BigInt.from(101))],
        {'second': 'Est. 1–3 min'},
      ),
      isNull,
    );
  });

  test(
    'multi-leg Card ETA survives identical resume lists and rechecks changed status',
    () async {
      final link = VizorPaymentLink(
        label: 'Gift card',
        network: 'mainnet',
        address: 'card',
        amountZatoshi: BigInt.one,
        mnemonic: 'test-only',
        birthdayHeight: 1,
        createdAt: started,
      );
      final record = PaymentLinkReceivedRecord.fromLink(link).copyWith(
        status: PaymentLinkReceivedStatus.receiving,
        destinationAccountUuid: 'a',
        claimTxids: 'first,second',
        claimSubmittedAt: started,
      );
      final index = GiftCardActivityIndex.forAccount(
        accountUuid: 'a',
        createdRecords: [],
        receivedRecords: [record],
      );
      for (final fail in [false, true]) {
        final completer = Completer<List<rust_sync.TransactionInfo>>();
        final refreshed = Completer<List<rust_sync.TransactionInfo>>();
        var reads = 0;
        final sync = FakeSyncNotifier(
          SyncState(
            accountUuid: 'a',
            hasAccountScopedData: true,
            isSyncComplete: true,
            scannedHeight: 100,
            chainTipHeight: 100,
            recentTransactions: [
              _tx('first', mined: BigInt.from(99)),
              _tx('second'),
            ],
          ),
        );
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            accountProvider.overrideWith(_Accounts.new),
            syncProvider.overrideWith(() => sync),
            activityEtaClockProvider.overrideWithValue(() => started),
            giftCardActivityIndexProvider(
              'a',
            ).overrideWith((ref) async => index),
            swapActivityRecordsProvider('a').overrideWith((ref) async => []),
            activityEtaClaimHistoryLoaderProvider.overrideWithValue((
              account,
              network,
            ) {
              expect(account, 'a');
              reads++;
              return reads == 1 ? completer.future : refreshed.future;
            }),
          ],
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        await container.read(syncProvider.future);
        await container.read(giftCardActivityIndexProvider('a').future);
        await container.read(swapActivityRecordsProvider('a').future);
        final controller = container.read(
          pendingActivityEvidenceProvider.notifier,
        );
        controller.observe(accountUuid: 'a', txids: ['first', 'second']);
        controller.networkChecked(100);
        expect(
          container.read(activityEtaLabelsProvider)['gift-card:card'],
          isNull,
        );
        final load = container.read(activityEtaClaimHistoryProvider.future);
        if (fail) {
          completer.completeError(StateError('history unavailable'));
          await expectLater(load, throwsStateError);
        } else {
          completer.complete([
            _tx('first', mined: BigInt.from(99)),
            _tx('second'),
          ]);
          await load;
        }
        expect(
          container.read(activityEtaLabelsProvider)['gift-card:card'],
          fail ? isNull : 'Est. 1–3 min',
        );
        if (!fail) {
          final snapshot = container.read(syncProvider).value!;
          sync.emit(
            snapshot.copyWith(
              recentTransactions: [
                _tx('first', mined: BigInt.from(99)),
                _tx('second'),
              ],
            ),
          );
          await container.pump();
          expect(reads, 1);
          expect(
            container.read(activityEtaLabelsProvider)['gift-card:card'],
            'Est. 1–3 min',
          );
          sync.emit(
            snapshot.copyWith(
              recentTransactions: [
                _tx('first', mined: BigInt.from(99)),
                _tx('second', mined: BigInt.from(100)),
              ],
            ),
          );
          expect(
            container.read(activityEtaLabelsProvider)['gift-card:card'],
            isNull,
          );
          final nextRead = container.read(
            activityEtaClaimHistoryProvider.future,
          );
          expect(reads, 2);
          refreshed.complete([
            _tx('first', mined: BigInt.from(99)),
            _tx('second', mined: BigInt.from(100)),
          ]);
          await nextRead;
          expect(
            container.read(activityEtaLabelsProvider)['gift-card:card'],
            isNull,
          );
        }
        controller.clear();
      }
    },
  );

  test(
    'a visible refunded Pay deposit remains excluded from ordinary ETA',
    () async {
      final id = '01' * 31 + '02';
      final record = SwapIntentRecord(
        id: 'pay',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '1 ZEC',
        receiveEstimateText: '1 USDC',
        status: SwapIntentStatus.refunded,
        nextAction: 'Refunded',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        payMode: true,
        depositTxHash: id,
        createdAt: started,
        updatedAt: started,
      );
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_Accounts.new),
          swapActivityRecordsProvider(
            'a',
          ).overrideWith((ref) async => [record]),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(swapActivityRecordsProvider('a').future);
      expect(
        container.read(activityEtaExcludedTxidsProvider),
        contains(activityTxidKey(id)),
      );
    },
  );

  test(
    'Home and Activity consume only complete account-scoped sync snapshots',
    () async {
      final synced = SyncState(
        accountUuid: 'a',
        hasAccountScopedData: true,
        isSyncComplete: true,
        scannedHeight: 100,
        chainTipHeight: 100,
      );
      final sync = FakeSyncNotifier(synced);
      final container = ProviderContainer(
        overrides: [
          accountProvider.overrideWith(_Accounts.new),
          giftCardActivityIndexProvider(
            'a',
          ).overrideWith((ref) async => GiftCardActivityIndex.empty),
          swapActivityRecordsProvider('a').overrideWith((ref) async => []),
          syncProvider.overrideWith(() => sync),
          activityEtaClockProvider.overrideWithValue(() => started),
        ],
      );
      addTearDown(container.dispose);
      await container.read(accountProvider.future);
      await container.read(syncProvider.future);
      final evidence = container.read(pendingActivityEvidenceProvider.notifier);
      evidence.observe(accountUuid: 'a', txids: ['tx']);
      evidence.observe(accountUuid: 'b', txids: ['foreign']);
      evidence.networkChecked(100);
      await container.read(giftCardActivityIndexProvider('a').future);
      await container.read(swapActivityRecordsProvider('a').future);
      expect(container.read(activityEtaLabelsProvider)['tx'], 'Est. 1–3 min');
      for (final unavailable in [
        synced.copyWith(isSyncing: true),
        synced.copyWith(isSyncComplete: false),
        synced.copyWith(scannedHeight: 99),
        SyncState(
          accountUuid: 'b',
          hasAccountScopedData: true,
          isSyncComplete: true,
          scannedHeight: 100,
        ),
        SyncState(accountUuid: 'a', isSyncComplete: true, scannedHeight: 100),
      ]) {
        sync.emit(unavailable);
        expect(container.read(activityEtaLabelsProvider), isEmpty);
      }
    },
  );
}

rust_sync.TransactionInfo _tx(
  String id, {
  BigInt? mined,
  bool expired = false,
  String? parent,
  BigInt? parentHeight,
  bool? parentExpired,
}) => rust_sync.TransactionInfo(
  txidHex: id,
  minedHeight: mined ?? BigInt.zero,
  expiredUnmined: expired,
  accountBalanceDelta: 0,
  fee: BigInt.zero,
  blockTime: BigInt.zero,
  isTransparent: false,
  txKind: mined == null ? 'receiving' : 'received',
  displayAmount: BigInt.one,
  displayPool: 'shielded',
  createdTime: BigInt.zero,
  fundingParentTxid: parent,
  fundingParentMinedHeight: parentHeight,
  fundingParentExpired: parentExpired,
);
