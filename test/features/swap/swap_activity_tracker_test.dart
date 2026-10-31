import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_operation_lifecycle.dart';
import 'package:zcash_wallet/src/features/swap/integrations/near_intents/near_intents_one_click_swap_adapter.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_deposit_broadcast_result.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';

void main() {
  test(
    'automatic refresh skips unsigned ZEC deposits but tracks created ones',
    () async {
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({});
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
      );
      final intents = [
        _intent(
          id: 'unsigned',
          depositAddress: 'unsigned',
          depositTxHash: null,
        ),
        _intent(id: 'unbroadcast', depositAddress: 'unbroadcast').copyWith(
          broadcastStatus: SwapDepositBroadcastStatus.pendingBroadcast,
        ),
      ];
      await tracker.saveIntents(accountUuid: 'account-1', intents: intents);

      // Sync resubmits a created deposit whose first broadcast failed.
      final result = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: intents,
      );
      expect(result.didRefresh, isTrue);
      expect(provider.statusRequests, ['unbroadcast']);

      provider.statusRequests.clear();
      await SwapActivityStatusRefresher(
        tracker: tracker,
      ).refreshOpenActivities(accountUuid: 'account-1', force: true);
      expect(provider.statusRequests, ['unbroadcast']);
    },
  );

  test(
    'automatic refresh discovers external deposits without a claim',
    () async {
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({
        'external': _snapshot(
          id: 'external',
          depositAddress: 'external',
          status: SwapIntentStatus.awaitingExternalDeposit,
        ),
      });
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
      );
      final intent = _intent(
        id: 'external',
        depositAddress: 'external',
        depositTxHash: null,
        status: SwapIntentStatus.awaitingExternalDeposit,
      ).copyWith(direction: SwapDirection.externalToZec);
      await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);

      // Home/Activity must also keep an unclaimed external deposit fresh.
      await SwapActivityStatusRefresher(
        tracker: tracker,
      ).refreshOpenActivities(accountUuid: 'account-1');
      expect(provider.statusRequests, ['external']);
      final waiting = await tracker.loadIntents(accountUuid: 'account-1');
      expect(waiting.single.status, SwapIntentStatus.awaitingExternalDeposit);
      expect(waiting.single.depositClaimedAt, isNull);

      provider.statuses['external'] = _snapshot(
        id: 'external',
        depositAddress: 'external',
        status: SwapIntentStatus.depositObserved,
      );
      final observed = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: waiting,
      );
      expect(provider.statusRequests, ['external', 'external']);
      expect(observed.intents.single.status, SwapIntentStatus.depositObserved);
      expect(observed.intents.single.depositClaimedAt, isNull);

      provider.statuses['external'] = _snapshot(
        id: 'external',
        depositAddress: 'external',
        status: SwapIntentStatus.complete,
      );
      final completed = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: observed.intents,
      );
      await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: completed.intents,
      );
      expect(provider.statusRequests, ['external', 'external', 'external']);
    },
  );

  for (final direction in SwapDirection.values) {
    test(
      '${direction.name} tracking survives an unknown provider status without deposit evidence',
      () async {
        final store = _MemorySwapActivityStore();
        final provider = _StatusSwapProvider({});
        final tracker = SwapActivityTracker(
          activityStore: store,
          swapProvider: provider,
        );
        final intent = _intent(
          id: 'unknown',
          depositAddress: 'unknown',
          depositTxHash: null,
          status: SwapIntentStatus.providerStatusUnknown,
        ).copyWith(direction: direction);
        await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);

        await tracker.refreshOpenIntents(
          accountUuid: 'account-1',
          currentIntents: [intent],
        );
        expect(provider.statusRequests, ['unknown']);
      },
    );
  }

  test('ZEC tracking continues after processing becomes unknown', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({
      'unknown': _snapshot(
        id: 'unknown',
        depositAddress: 'unknown',
        status: SwapIntentStatus.providerStatusUnknown,
      ),
    });
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final intent = _intent(
      id: 'unknown',
      depositAddress: 'unknown',
      depositTxHash: null,
      status: SwapIntentStatus.processing,
    );
    await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);

    final unknown = await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [intent],
    );
    expect(
      unknown.intents.single.status,
      SwapIntentStatus.providerStatusUnknown,
    );
    expect(unknown.intents.single.hasConfirmedDepositEvidence, isFalse);
    expect(unknown.intents.single.hasProviderObservedDepositEvidence, isFalse);

    provider.statuses['unknown'] = _snapshot(
      id: 'unknown',
      depositAddress: 'unknown',
      status: SwapIntentStatus.complete,
    );
    await SwapActivityStatusRefresher(
      tracker: tracker,
    ).refreshOpenActivities(accountUuid: 'account-1', force: true);

    expect(provider.statusRequests, ['unknown', 'unknown']);
    final completed = await tracker.loadIntents(accountUuid: 'account-1');
    expect(completed.single.status, SwapIntentStatus.complete);
  });

  test(
    'automatic refresh tracks claimed, broadcast and observed deposits',
    () async {
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({});
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
      );
      final intents = [
        _intent(
          id: 'claimed',
          depositAddress: 'claimed',
          depositTxHash: null,
          status: SwapIntentStatus.awaitingExternalDeposit,
        ).copyWith(
          direction: SwapDirection.externalToZec,
          depositClaimedAt: DateTime.now().toUtc(),
        ),
        _intent(id: 'broadcast', depositAddress: 'broadcast'),
        _intent(
          id: 'origin',
          depositAddress: 'origin',
          depositTxHash: null,
        ).copyWith(originChainTxHash: 'observed-origin-tx'),
        _intent(
          id: 'amount',
          depositAddress: 'amount',
          depositTxHash: null,
        ).copyWith(
          providerRefundInfo: const SwapProviderRefundInfo(
            depositedAmountText: '1 ZEC',
          ),
        ),
        for (final status in [
          SwapIntentStatus.depositObserved,
          SwapIntentStatus.processing,
          SwapIntentStatus.incompleteDeposit,
        ])
          _intent(
            id: status.name,
            depositAddress: status.name,
            status: status,
            depositTxHash: null,
          ),
      ];
      await tracker.saveIntents(accountUuid: 'account-1', intents: intents);
      await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: intents,
      );
      expect(
        provider.statusRequests,
        intents.map((intent) => intent.depositAddress).toList(),
      );
    },
  );

  test(
    'explicit deposit check works before automatic tracking starts',
    () async {
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({});
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
      );
      final intent = _intent(
        id: 'external',
        depositAddress: 'external',
        depositTxHash: null,
        status: SwapIntentStatus.awaitingExternalDeposit,
      ).copyWith(direction: SwapDirection.externalToZec);
      await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);
      await tracker.refreshIntent(
        accountUuid: 'account-1',
        currentIntents: [intent],
        intentId: intent.id,
      );
      expect(provider.statusRequests, ['external']);
    },
  );

  test('refreshes every open activity for the active account', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({
      'deposit-a': _snapshot(
        id: 'swap-a',
        depositAddress: 'deposit-a',
        status: SwapIntentStatus.processing,
      ),
      'deposit-b': _snapshot(
        id: 'swap-b',
        depositAddress: 'deposit-b',
        status: SwapIntentStatus.complete,
      ),
    });
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final persistedIntents = [
      _intent(id: 'swap-a', depositAddress: 'deposit-a'),
      _intent(
        id: 'swap-b',
        depositAddress: 'deposit-b',
        status: SwapIntentStatus.depositObserved,
      ),
      _intent(
        id: 'swap-c',
        depositAddress: 'deposit-c',
        status: SwapIntentStatus.complete,
      ),
    ];
    store.savedRecords = [
      for (final intent in persistedIntents)
        SwapIntentRecord.fromIntent(intent),
    ];

    final result = await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [persistedIntents.first],
    );

    expect(provider.statusRequests, ['deposit-a', 'deposit-b']);
    expect(result.intents.map((intent) => intent.status), [
      SwapIntentStatus.processing,
      SwapIntentStatus.complete,
      SwapIntentStatus.complete,
    ]);
    expect(store.savedRecords, hasLength(3));
    expect(store.savedRecords.map((record) => record.status), [
      SwapIntentStatus.processing,
      SwapIntentStatus.complete,
      SwapIntentStatus.complete,
    ]);
  });

  test('does not refresh or save hidden terminal-only activity', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final currentIntents = [
      _intent(
        id: 'swap-complete',
        depositAddress: 'deposit-complete',
        status: SwapIntentStatus.complete,
      ),
      _intent(
        id: 'swap-failed',
        depositAddress: 'deposit-failed',
        status: SwapIntentStatus.failed,
      ),
    ];

    final result = await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: currentIntents,
    );

    expect(result.didRefresh, isFalse);
    expect(provider.statusRequests, isEmpty);
    expect(store.saveCount, 0);
  });

  test(
    'refresh does not resurrect an intent removed while status is loading',
    () async {
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({
        'deposit-a': _snapshot(
          id: 'swap-a',
          depositAddress: 'deposit-a',
          status: SwapIntentStatus.processing,
        ),
      });
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
      );
      final persistedIntent = _intent(
        id: 'swap-a',
        depositAddress: 'deposit-a',
      );
      store.savedRecords = [SwapIntentRecord.fromIntent(persistedIntent)];
      provider.onGetStatus = (_) async {
        store.savedRecords = const [];
      };

      await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [persistedIntent],
      );

      expect(provider.statusRequests, ['deposit-a']);
      expect(store.savedRecords, isEmpty);
    },
  );

  test('refresh keeps intents added while status is loading', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({
      'deposit-a': _snapshot(
        id: 'swap-a',
        depositAddress: 'deposit-a',
        status: SwapIntentStatus.processing,
      ),
    });
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final persistedIntent = _intent(id: 'swap-a', depositAddress: 'deposit-a');
    final addedIntent = _intent(id: 'swap-b', depositAddress: 'deposit-b');
    store.savedRecords = [SwapIntentRecord.fromIntent(persistedIntent)];
    provider.onGetStatus = (_) async {
      store.savedRecords = [
        ...store.savedRecords,
        SwapIntentRecord.fromIntent(addedIntent),
      ];
    };

    await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [persistedIntent],
    );

    expect(provider.statusRequests, ['deposit-a']);
    expect(store.savedRecords.map((record) => record.id), ['swap-a', 'swap-b']);
    expect(store.savedRecords.map((record) => record.status), [
      SwapIntentStatus.processing,
      SwapIntentStatus.awaitingDeposit,
    ]);
  });

  test('status refresher throttles repeated activity refreshes', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final refresher = SwapActivityStatusRefresher(
      tracker: tracker,
      minInterval: const Duration(minutes: 1),
    );
    store.savedRecords = [
      SwapIntentRecord.fromIntent(
        _intent(id: 'swap-a', depositAddress: 'deposit-a'),
      ),
    ];

    await refresher.refreshOpenActivities(
      accountUuid: 'account-1',
      force: true,
    );
    await refresher.refreshOpenActivities(accountUuid: 'account-1');

    expect(provider.statusRequests, ['deposit-a']);

    await refresher.refreshOpenActivities(
      accountUuid: 'account-1',
      force: true,
    );

    expect(provider.statusRequests, ['deposit-a', 'deposit-a']);
  });

  test('status refresher skips recently checked persisted activity', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final refresher = SwapActivityStatusRefresher(
      tracker: tracker,
      minInterval: const Duration(minutes: 1),
    );
    store.savedRecords = [
      SwapIntentRecord.fromIntent(
        _intent(
          id: 'swap-recent',
          depositAddress: 'deposit-recent',
        ).copyWith(lastStatusCheckedAt: DateTime.now().toUtc()),
      ),
    ];

    await refresher.refreshOpenActivities(accountUuid: 'account-1');

    expect(provider.statusRequests, isEmpty);
  });

  test('expired incoming swaps need no scan-watch reclaim polling', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    await tracker.saveIntents(
      accountUuid: 'account-1',
      intents: [
        _intent(
          id: 'expired',
          depositAddress: 'expired',
          depositTxHash: null,
          status: SwapIntentStatus.expired,
        ).copyWith(
          direction: SwapDirection.externalToZec,
          oneClickRecipient: 'u1swap',
          depositDeadline: DateTime.now().toUtc().subtract(
            const Duration(days: 2),
          ),
        ),
      ],
    );
    await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [],
    );
    expect(provider.statusRequests, isEmpty);
  });

  test(
    'an expired private quote is polled until the wallet releases it',
    () async {
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({
        'private': _snapshot(
          id: 'private',
          depositAddress: 'private',
          status: SwapIntentStatus.awaitingExternalDeposit,
        ),
      });
      // The wallet still holds the slot on the first poll and frees it there.
      final tracked = [true, false];
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
        onProviderSnapshot: (_, _, _) async => tracked.removeAt(0),
      );
      final intent =
          _intent(
            id: 'private',
            depositAddress: 'private',
            depositTxHash: null,
            status: SwapIntentStatus.expired,
          ).copyWith(
            direction: SwapDirection.externalToZec,
            privateAddress: true,
            depositDeadline: DateTime.now().toUtc().subtract(
              const Duration(days: 2),
            ),
          );
      await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);
      for (var poll = 0; poll < 3; poll++) {
        await tracker.refreshOpenIntents(
          accountUuid: 'account-1',
          currentIntents: [],
        );
      }
      expect(provider.statusRequests, ['private', 'private']);
      final stored = await tracker.loadIntents(accountUuid: 'account-1');
      expect(stored.single.status, SwapIntentStatus.expired);
      expect(stored.single.walletReleased, isTrue);
    },
  );

  test('only private swaps share statuses with the wallet', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final recorded = <String>[];
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
      onProviderSnapshot: (intent, _, _) async {
        recorded.add(intent.id);
        return true;
      },
    );
    final intents = [
      _intent(id: 'ordinary', depositAddress: 'ordinary'),
      _intent(
        id: 'private',
        depositAddress: 'private',
      ).copyWith(privateAddress: true),
    ];
    await tracker.saveIntents(accountUuid: 'account-1', intents: intents);
    await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: intents,
    );
    expect(provider.statusRequests, unorderedEquals(['ordinary', 'private']));
    expect(recorded, ['private']);
  });

  test('a started swap whose final save failed is still polled and saved '
      'started', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    // Created in this launch, after the tracker.
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final starting =
        _intent(
          id: 'private',
          depositAddress: 'private',
          status: SwapIntentStatus.awaitingExternalDeposit,
        ).copyWith(
          direction: SwapDirection.externalToZec,
          privateAddress: true,
          startPending: true,
          createdAt: DateTime.now().toUtc(),
        );
    await tracker.saveIntents(accountUuid: 'account-1', intents: [starting]);
    // The save that would store it started fails once.
    store.onSave = () async {
      store.onSave = null;
      throw StateError('secure storage unavailable');
    };
    await expectLater(
      tracker.finishStart(accountUuid: 'account-1', intentId: 'private'),
      throwsStateError,
    );
    expect(store.savedRecords.single.startPending, isTrue);

    await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: const [],
    );

    expect(provider.statusRequests, ['private']);
    expect(store.savedRecords.single.startPending, isFalse);
    expect(store.savedRecords.single.status, SwapIntentStatus.processing);
  });

  test('wallet deletion waits for saved private swap activity', () async {
    final lifecycle = LedgerOperationLifecycle();
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
      lifecycle: lifecycle,
      onProviderSnapshot: (_, _, _) async => true,
    );
    final private = _intent(
      id: 'private',
      depositAddress: 'private',
    ).copyWith(privateAddress: true);
    await tracker.saveIntents(accountUuid: 'account-1', intents: [private]);
    final held = Completer<void>();
    var saving = false;
    store.onSave = () {
      saving = true;
      return held.future;
    };
    final refresh = tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [private],
    );
    await pumpEventQueue();
    expect(saving, isTrue, reason: 'the status arrived and its save started');

    var drained = false;
    unawaited(lifecycle.quiesceAndDrain().then((_) => drained = true));
    await pumpEventQueue();
    expect(drained, isFalse, reason: 'deletion waits for the activity write');
    held.complete();
    await refresh;
    await pumpEventQueue();
    expect(drained, isTrue);
    lifecycle.resume();
  });

  test('a replacement save writes without reading what it replaces', () async {
    final store = _MemorySwapActivityStore();
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: _StatusSwapProvider({}),
    );
    await tracker.saveIntents(
      accountUuid: 'account-1',
      intents: [_intent(id: 'swap', depositAddress: 'swap')],
    );
    expect(store.saveCount, 1);
    expect(store.loadCount, 0);
  });

  test('ordinary swaps stay outside the wallet deletion drain', () async {
    final lifecycle = LedgerOperationLifecycle();
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final held = Completer<void>();
    provider.onGetStatus = (_) => held.future;
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
      lifecycle: lifecycle,
      onProviderSnapshot: (_, _, _) async => true,
    );
    final ordinary = _intent(id: 'ordinary', depositAddress: 'ordinary');
    await tracker.saveIntents(accountUuid: 'account-1', intents: [ordinary]);
    final refresh = tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [ordinary],
    );
    await pumpEventQueue();
    expect(provider.statusRequests, ['ordinary']);

    var drained = false;
    unawaited(lifecycle.quiesceAndDrain().then((_) => drained = true));
    await pumpEventQueue();
    expect(drained, isTrue, reason: 'deletion skips the held status request');
    // Loads and saves keep working while deletion holds admission.
    expect(await tracker.loadIntents(accountUuid: 'account-1'), hasLength(1));
    await tracker.saveIntents(accountUuid: 'account-1', intents: [ordinary]);
    held.complete();
    expect((await refresh).didRefresh, isTrue);
    lifecycle.resume();
  });

  test(
    'a private swap status refresh holds the wallet deletion drain',
    () async {
      final lifecycle = LedgerOperationLifecycle();
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({});
      final held = Completer<void>();
      provider.onGetStatus = (_) => held.future;
      final recorded = <String>[];
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
        lifecycle: lifecycle,
        onProviderSnapshot: (intent, _, _) async {
          recorded.add(intent.id);
          return true;
        },
      );
      final private = _intent(
        id: 'private',
        depositAddress: 'private',
      ).copyWith(privateAddress: true);
      await tracker.saveIntents(accountUuid: 'account-1', intents: [private]);
      final refresh = tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [private],
      );
      await pumpEventQueue();

      var drained = false;
      unawaited(lifecycle.quiesceAndDrain().then((_) => drained = true));
      await pumpEventQueue();
      expect(drained, isFalse, reason: 'its result still writes the wallet');
      held.complete();
      await refresh;
      await pumpEventQueue();
      expect(drained, isTrue);
      expect(recorded, ['private']);

      // No private refresh starts while deletion runs.
      final skipped = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [private],
      );
      expect(skipped.didRefresh, isFalse);
      expect(provider.statusRequests, ['private']);
      lifecycle.resume();
    },
  );

  test(
    'a completed status without its token completes only private swaps',
    () async {
      // A flexible-input swap quoted 70 USDC, then paid out less. Its external
      // token has left NEAR's catalog, so the status cannot state the payout.
      final completed = SwapIntentSnapshot(
        id: 'swap',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> Unlisted token',
        sellAmountText: 'Not reported',
        receiveEstimateText: 'Not reported',
        status: SwapIntentStatus.complete,
        nextAction: 'Swap completed',
        depositInstruction: const SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: 'swap',
          expiresInLabel: '01:30',
          reuseWarning: 'Do not reuse this address',
        ),
        providerStatusRaw: 'SUCCESS',
        amountOutBaseUnits: '35000000',
        statusOnly: true,
      );
      final store = _MemorySwapActivityStore();
      final provider = _StatusSwapProvider({});
      provider.onGetStatus = (_) async => throw OneClickStatusOnlyException(
        'NEAR Intents does not currently list USDC',
        snapshot: completed,
      );
      final tracker = SwapActivityTracker(
        activityStore: store,
        swapProvider: provider,
        onProviderSnapshot: (_, _, _) async => true,
      );

      // An ordinary swap fails the refresh, as before private swaps existed, and
      // never shows the quoted 70 USDC as its completed amount.
      final ordinary = _intent(id: 'swap', depositAddress: 'swap');
      await tracker.saveIntents(accountUuid: 'account-1', intents: [ordinary]);
      final failed = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [ordinary],
      );
      expect(failed.refreshError, isNotNull);
      expect(failed.intents.single.status, SwapIntentStatus.awaitingDeposit);
      expect(failed.intents.single.receiveEstimate, '70.00 USDC');

      // A private swap still takes the status, which its wallet records need.
      final private = ordinary.copyWith(privateAddress: true);
      await tracker.saveIntents(accountUuid: 'account-1', intents: [private]);
      final refreshed = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [private],
      );
      expect(refreshed.refreshError, isNull);
      expect(refreshed.intents.single.status, SwapIntentStatus.complete);
    },
  );

  test('a swap the wallet no longer tracks is marked released', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracked = {'held': true, 'released': false};
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
      onProviderSnapshot: (intent, _, _) async => tracked[intent.id],
    );
    final intents = [
      for (final id in tracked.keys)
        _intent(id: id, depositAddress: id).copyWith(privateAddress: true),
    ];
    await tracker.saveIntents(accountUuid: 'account-1', intents: intents);
    await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: intents,
    );
    final stored = await tracker.loadIntents(accountUuid: 'account-1');
    expect(stored.swapIntentById('held')?.walletReleased, isFalse);
    expect(stored.swapIntentById('released')?.walletReleased, isTrue);
  });

  /// Each 1Click status, as the adapter maps it, and whether it ends polling.
  /// `expired` never comes from 1Click; the app derives it from the deadline.
  const terminality = <SwapIntentStatus, bool>{
    SwapIntentStatus.awaitingExternalDeposit: false, // PENDING_DEPOSIT
    SwapIntentStatus.awaitingDeposit: false, // PENDING_DEPOSIT, ZEC in
    SwapIntentStatus.depositObserved: false, // KNOWN_DEPOSIT_TX
    SwapIntentStatus.processing: false, // PROCESSING
    SwapIntentStatus.incompleteDeposit: false, // INCOMPLETE_DEPOSIT
    SwapIntentStatus.providerStatusUnknown: false, // anything else
    SwapIntentStatus.complete: true, // SUCCESS
    SwapIntentStatus.refunded: true, // REFUNDED
    SwapIntentStatus.failed: true, // FAILED
    SwapIntentStatus.expired: true,
  };

  /// Pins which statuses are conclusive, since the wallet stops polling, and
  /// so stops reporting to the wallet, at exactly these.
  test('only SUCCESS, REFUNDED, FAILED and local expiry are terminal', () {
    expect({
      for (final status in SwapIntentStatus.values) status: status.isTerminal,
    }, terminality);
  });

  for (final MapEntry(key: status, value: terminal) in terminality.entries) {
    if (status == SwapIntentStatus.expired) continue;

    /// A wallet failure on a non-terminal status is logged and swallowed, and
    /// the refresh takes the status. On a terminal one it fails the refresh
    /// and keeps the swap open. Either way the next poll records it again.
    test('a failed wallet record of ${status.name} is retried by the next '
        'poll', () async {
      final provider = _StatusSwapProvider({
        'private': _snapshot(
          id: 'private',
          depositAddress: 'private',
          status: status,
        ),
      });
      var failures = 1;
      final recorded = <SwapIntentStatus>[];
      final tracker = SwapActivityTracker(
        activityStore: _MemorySwapActivityStore(),
        swapProvider: provider,
        onProviderSnapshot: (_, snapshot, _) async {
          if (failures-- > 0) throw StateError('database is locked');
          recorded.add(snapshot.status);
          return true;
        },
      );
      final intent = _privateIncoming();
      await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);

      final first = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [intent],
      );
      expect(
        first.refreshError,
        terminal ? isNotNull : isNull,
        reason: 'only a terminal status fails the refresh',
      );
      if (!terminal) expect(first.intents.single.status, status);
      final stored = await tracker.loadIntents(accountUuid: 'account-1');
      expect(stored.single.status.isTerminal, isFalse);

      final second = await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: stored,
      );
      expect(second.refreshError, isNull);
      expect(provider.statusRequests, hasLength(2));
      expect(recorded, [status]);
    });
  }

  /// The poll that first sees PENDING_DEPOSIT after the deposit deadline is
  /// the wallet's evidence that the started quote ended, which releases its
  /// receive index. The app resolves that poll to `expired`, but the snapshot
  /// it records is not terminal, so a wallet failure there is only logged.
  /// The swap stays polled until the wallet reports the address released, so
  /// the next poll records the status again. Here the deadline arrives with
  /// the status, as 1Click reports it.
  test(
    'a failed record of the post-deadline status keeps the swap polled',
    () async {
      final provider = _StatusSwapProvider({
        'private': _snapshot(
          id: 'private',
          depositAddress: 'private',
          status: SwapIntentStatus.awaitingExternalDeposit,
          deadline: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        ),
      });
      var failures = 1;
      final recorded = <SwapIntentStatus>[];
      final tracker = SwapActivityTracker(
        activityStore: _MemorySwapActivityStore(),
        swapProvider: provider,
        onProviderSnapshot: (_, snapshot, _) async {
          if (failures-- > 0) throw StateError('database is locked');
          recorded.add(snapshot.status);
          return true;
        },
      );
      final intent = _privateIncoming(noDeadline: true);
      await tracker.saveIntents(accountUuid: 'account-1', intents: [intent]);
      await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: [intent],
      );
      expect(provider.statusRequests, hasLength(1), reason: 'it was polled');
      expect(failures, lessThan(1), reason: 'and its record failed');
      final stored = await tracker.loadIntents(accountUuid: 'account-1');
      expect(stored.single.status, SwapIntentStatus.expired);
      await tracker.refreshOpenIntents(
        accountUuid: 'account-1',
        currentIntents: stored,
      );
      expect(recorded, [
        SwapIntentStatus.awaitingExternalDeposit,
      ], reason: 'the next poll records the status the wallet missed');
    },
  );

  test('status refresh over Tor names the blocked route', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    provider.onGetStatus = (_) async {
      throw const OneClickApiException(
        'NEAR Intents status failed (403): Request blocked',
        operation: 'status',
        statusCode: 403,
        responseBody:
            '<html><h1>Request blocked</h1><p>Generated by cloudfront</p></html>',
      );
    };
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
      isTorEnabled: () => true,
    );
    final intent = _intent(id: 'swap-a', depositAddress: 'deposit-a');
    store.savedRecords = [SwapIntentRecord.fromIntent(intent)];

    final result = await tracker.refreshIntent(
      accountUuid: 'account-1',
      currentIntents: [intent],
      intentId: 'swap-a',
    );

    const expectedMessage =
        'Swap is unavailable over Tor because the service blocked this '
        'connection.\nTurn off Tor in Settings to use swap.';
    expect(result.refreshError, expectedMessage);
    expect(result.intents.single.statusError, expectedMessage);
    expect(store.savedRecords.single.statusError, expectedMessage);
  });
}

SwapIntent _intent({
  required String id,
  required String depositAddress,
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
  String? depositTxHash = 'broadcast-deposit-tx',
}) {
  return SwapIntent(
    id: id,
    pair: 'ZEC -> USDC',
    sellAmount: '1.0000 ZEC',
    receiveEstimate: '70.00 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Checking swap status',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: depositAddress,
    depositTxHash: depositTxHash,
    providerQuoteId: 'quote-$id',
    accountUuid: 'account-1',
  );
}

SwapIntentSnapshot _snapshot({
  required String id,
  required String depositAddress,
  required SwapIntentStatus status,
  DateTime? deadline,
}) {
  return SwapIntentSnapshot(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1.0000 ZEC',
    receiveEstimateText: '70.00 USDC',
    status: status,
    nextAction: 'Provider status updated',
    depositInstruction: SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: depositAddress,
      expiresInLabel: '01:30',
      reuseWarning: 'Do not reuse this address',
      deadline: deadline,
    ),
  );
}

/// An open incoming swap quoted with a one-time (private) address, whose
/// deposit deadline is an hour from now, or unknown with `noDeadline`.
SwapIntent _privateIncoming({bool noDeadline = false}) =>
    _intent(
      id: 'private',
      depositAddress: 'private',
      status: SwapIntentStatus.awaitingExternalDeposit,
      depositTxHash: null,
    ).copyWith(
      direction: SwapDirection.externalToZec,
      privateAddress: true,
      depositDeadline: noDeadline
          ? null
          : DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

class _MemorySwapActivityStore implements SwapActivityStore {
  var saveCount = 0;
  var loadCount = 0;
  List<SwapIntentRecord> savedRecords = const [];

  /// Runs before each save, for tests that hold a write.
  Future<void> Function()? onSave;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    loadCount++;
    return savedRecords;
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    await onSave?.call();
    saveCount++;
    savedRecords = records;
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    savedRecords = const [];
  }
}

class _StatusSwapProvider implements SwapProvider {
  _StatusSwapProvider(this.statuses);

  final Map<String, SwapIntentSnapshot> statuses;
  final statusRequests = <String>[];
  Future<void> Function(String intentId)? onGetStatus;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async => const [];

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(intentId);
    await onGetStatus?.call(intentId);
    return statuses[intentId] ??
        _snapshot(
          id: intentId,
          depositAddress: intentId,
          status: SwapIntentStatus.processing,
        );
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) {
    throw UnimplementedError();
  }
}
