// Scenario tests for how swap status polling hands provider statuses to the
// wallet for swaps quoted with a one-time (private) address. See
// docs/near-swap-receiving.md and `SwapActivityTracker.recordProviderSnapshot`.
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';

const _account = 'account-1';

void main() {
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
    /// the next poll records it again. On a terminal one it fails the refresh
    /// and keeps the swap open, so the next poll records it again too.
    test('a failed wallet record of ${status.name} is retried by the next '
        'poll', () async {
      final provider = _StatusProvider()..next = status;
      var failures = 1;
      final recorded = <SwapIntentStatus>[];
      final tracker = _tracker(provider, (_, snapshot, _) async {
        if (failures-- > 0) throw StateError('database is locked');
        recorded.add(snapshot.status);
      });
      final intent = _privateIncoming();
      await tracker.saveIntents(accountUuid: _account, intents: [intent]);

      final first = await tracker.refreshOpenIntents(
        accountUuid: _account,
        currentIntents: [intent],
      );
      expect(
        first.refreshError,
        terminal ? isNotNull : isNull,
        reason: 'only a terminal status fails the refresh',
      );
      final stored = await tracker.loadIntents(accountUuid: _account);
      expect(stored.single.status.isTerminal, isFalse);

      await tracker.refreshOpenIntents(
        accountUuid: _account,
        currentIntents: stored,
      );
      expect(provider.requests, 2, reason: 'the swap is still polled');
      expect(recorded, [status]);
    });
  }

  /// A private swap stays private across polls, so every status until a
  /// conclusive one reaches the wallet, and polling stops after it.
  test('a private swap reports every status until a conclusive one', () async {
    final provider = _StatusProvider();
    final recorded = <SwapIntentStatus>[];
    final tracker = _tracker(
      provider,
      (_, snapshot, _) async => recorded.add(snapshot.status),
    );
    var intents = [_privateIncoming()];
    await tracker.saveIntents(accountUuid: _account, intents: intents);
    for (final status in [
      SwapIntentStatus.awaitingExternalDeposit,
      SwapIntentStatus.depositObserved,
      SwapIntentStatus.incompleteDeposit,
      SwapIntentStatus.processing,
      SwapIntentStatus.complete,
      // Not requested: the swap is conclusive.
      SwapIntentStatus.processing,
    ]) {
      provider.next = status;
      await tracker.refreshOpenIntents(
        accountUuid: _account,
        currentIntents: intents,
      );
      intents = await tracker.loadIntents(accountUuid: _account);
      expect(intents.single.privateAddress, isTrue);
    }
    expect(recorded, [
      SwapIntentStatus.awaitingExternalDeposit,
      SwapIntentStatus.depositObserved,
      SwapIntentStatus.incompleteDeposit,
      SwapIntentStatus.processing,
      SwapIntentStatus.complete,
    ]);
    expect(provider.requests, 5);
  });

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
      final provider = _StatusProvider()
        ..next = SwapIntentStatus.awaitingExternalDeposit
        ..deadline = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
      var failures = 1;
      final recorded = <SwapIntentStatus>[];
      final tracker = _tracker(provider, (_, snapshot, _) async {
        if (failures-- > 0) throw StateError('database is locked');
        recorded.add(snapshot.status);
      });
      final intent = _privateIncoming(noDeadline: true);
      await tracker.saveIntents(accountUuid: _account, intents: [intent]);
      await tracker.refreshOpenIntents(
        accountUuid: _account,
        currentIntents: [intent],
      );
      expect(provider.requests, 1, reason: 'the deadline poll ran');
      expect(failures, lessThan(1), reason: 'and its record failed');
      final stored = await tracker.loadIntents(accountUuid: _account);
      expect(stored.single.status, SwapIntentStatus.expired);
      await tracker.refreshOpenIntents(
        accountUuid: _account,
        currentIntents: stored,
      );
      expect(recorded, [
        SwapIntentStatus.awaitingExternalDeposit,
      ], reason: 'the next poll records the status the wallet missed');
    },
  );

  /// The deadline can also pass between polls, for example while the app is
  /// closed. The stored swap loads as expired and is still polled, so the
  /// wallet gets the post-deadline status that frees its slot.
  test(
    'a private quote whose deadline passed between polls is polled once more',
    () async {
      final provider = _StatusProvider()
        ..next = SwapIntentStatus.awaitingExternalDeposit;
      final recorded = <SwapIntentStatus>[];
      final tracker = _tracker(
        provider,
        (_, snapshot, _) async => recorded.add(snapshot.status),
      );
      final intent = _privateIncoming(
        deadline: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      await tracker.saveIntents(accountUuid: _account, intents: [intent]);
      await tracker.refreshOpenIntents(
        accountUuid: _account,
        currentIntents: [intent],
      );
      expect(recorded, [SwapIntentStatus.awaitingExternalDeposit]);
    },
  );
}

/// A tracker over an in-memory store that hands statuses to `onSnapshot`.
SwapActivityTracker _tracker(
  _StatusProvider provider,
  Future<void> Function(SwapIntent, SwapIntentSnapshot, DateTime) onSnapshot,
) => SwapActivityTracker(
  activityStore: _MemoryStore(),
  swapProvider: provider,
  // The wallet still tracks the address after every recorded status.
  onProviderSnapshot: (intent, snapshot, checkedAt) async {
    await onSnapshot(intent, snapshot, checkedAt);
    return true;
  },
);

/// An open incoming swap quoted with a reserved one-time address, whose
/// deposit deadline is `deadline` (an hour from now by default), or unknown
/// with `noDeadline`.
SwapIntent _privateIncoming({DateTime? deadline, bool noDeadline = false}) =>
    SwapIntent(
      id: 'private',
      pair: 'USDC -> ZEC',
      sellAmount: '25 USDC',
      receiveEstimate: '0.25 ZEC',
      provider: 'NEAR Intents',
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction: 'Send USDC',
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress: '0xdeposit',
      depositMemo: 'memo',
      providerQuoteId: 'quote-1',
      oneClickRecipient: 'u1onetime',
      depositDeadline: noDeadline
          ? null
          : deadline ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
      accountUuid: _account,
      privateAddress: true,
    );

/// Answers every status request with [next], counting requests. Other calls
/// fail.
class _StatusProvider extends Fake implements SwapProvider {
  SwapIntentStatus next = SwapIntentStatus.processing;

  /// The deposit deadline the status reports, if any.
  DateTime? deadline;
  var requests = 0;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async => const [];

  /// Returns [next] for `intentId`, reporting [deadline].
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    requests++;
    return SwapIntentSnapshot(
      id: intentId,
      providerLabel: providerLabel,
      pairText: 'USDC -> ZEC',
      sellAmountText: '25 USDC',
      receiveEstimateText: '0.25 ZEC',
      status: next,
      nextAction: next.label,
      providerStatusRaw: next.name,
      depositInstruction: SwapDepositInstruction(
        asset: SwapAsset.usdc,
        address: intentId,
        expiresInLabel: '10:00',
        reuseWarning: '',
        memo: depositMemo,
        deadline: deadline,
      ),
    );
  }
}

/// Keeps one account's records in memory.
class _MemoryStore implements SwapActivityStore {
  List<SwapIntentRecord> records = const [];

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async => records;

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async => this.records = records;

  @override
  Future<void> deleteForAccount({required String accountUuid}) async =>
      records = const [];
}
