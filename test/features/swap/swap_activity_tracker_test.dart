import 'package:flutter_test/flutter_test.dart';
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
    ),
  );
}

class _MemorySwapActivityStore implements SwapActivityStore {
  var saveCount = 0;
  List<SwapIntentRecord> savedRecords = const [];

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return savedRecords;
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
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
