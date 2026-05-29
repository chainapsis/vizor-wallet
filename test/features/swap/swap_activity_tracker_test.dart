import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';

void main() {
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
}

SwapIntent _intent({
  required String id,
  required String depositAddress,
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
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
