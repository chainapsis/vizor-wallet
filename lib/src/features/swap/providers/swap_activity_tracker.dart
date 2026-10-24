import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/network_privacy_provider.dart';
import '../../ledger/services/ledger_operation_lifecycle.dart';
import '../integrations/near_intents/near_intents_one_click_swap_adapter.dart'
    show OneClickStatusOnlyException;
import '../models/swap_intent_presentation_mapper.dart';
import '../models/swap_models.dart';
import 'swap_activity_store.dart';
import 'swap_failure_policy.dart';
import 'swap_provider_config.dart';
import 'swap_receive_reservation_service.dart';

const swapActivityStatusRefreshInterval = Duration(seconds: 30);

final swapActivityTrackerProvider = Provider<SwapActivityTracker>((ref) {
  return SwapActivityTracker(
    activityStore: ref.read(swapActivityStoreProvider),
    // Statuses reach the wallet as they are fetched, for swaps that quoted a
    // private address.
    onProviderSnapshot: (intent, snapshot, checkedAt) async {
      final account = intent.accountUuid;
      final direction = intent.direction;
      if (account == null || direction == null) return null;
      return ref
          .read(swapReceiveReservationServiceProvider)
          .observeStatus(
            account,
            direction: direction,
            depositAddress: intent.depositAddress ?? intent.id,
            memo: intent.depositMemo,
            snapshot: snapshot,
            checkedAt: checkedAt,
          );
    },
    lifecycle: ref.read(ledgerOperationLifecycleProvider),
    swapProvider: ref.read(swapIntentProvider),
    isTorEnabled: () => ref.read(networkPrivacyProvider).torEnabled,
    onRecordsChanged: () {
      ref.read(swapActivityRecordsRevisionProvider.notifier).bump();
    },
  );
});

final swapActivityStatusRefresherProvider =
    Provider<SwapActivityStatusRefresher>(
      (ref) => SwapActivityStatusRefresher(
        tracker: ref.read(swapActivityTrackerProvider),
      ),
    );

class SwapActivityRefreshResult {
  const SwapActivityRefreshResult({
    required this.intents,
    this.requestedIds = const <String>{},
    this.refreshError,
    this.didRefresh = false,
  });

  final List<SwapIntent> intents;
  final Set<String> requestedIds;
  final String? refreshError;
  final bool didRefresh;

  List<SwapIntent> reconcileInto(List<SwapIntent> currentIntents) {
    return currentIntents.reconcileRefreshedSwapIntents(
      refreshedIntents: intents,
      refreshedIds: requestedIds,
    );
  }

  bool hasRequestedCurrentIntent(List<SwapIntent> currentIntents) {
    return currentIntents.any((intent) => requestedIds.contains(intent.id));
  }

  bool includesRemovedRequestedIntent(List<SwapIntent> currentIntents) {
    final currentIds = {for (final intent in currentIntents) intent.id};
    return intents.any(
      (intent) =>
          requestedIds.contains(intent.id) && !currentIds.contains(intent.id),
    );
  }
}

class SwapActivityStatusRefresher {
  SwapActivityStatusRefresher({
    required SwapActivityTracker tracker,
    Duration minInterval = swapActivityStatusRefreshInterval,
  }) : _tracker = tracker,
       _minInterval = minInterval;

  final SwapActivityTracker _tracker;
  final Duration _minInterval;
  final Map<String, DateTime> _lastRefreshAt = {};
  final Map<String, Future<void>> _inFlight = {};

  Future<void> refreshOpenActivities({
    required String accountUuid,
    bool force = false,
  }) {
    final scopedAccountUuid = SwapActivityTracker.normalizeAccountUuid(
      accountUuid,
    );
    if (scopedAccountUuid == null) return Future.value();

    final running = _inFlight[scopedAccountUuid];
    if (running != null) return running;

    final now = DateTime.now().toUtc();
    final previous = _lastRefreshAt[scopedAccountUuid];
    if (!force && previous != null && now.difference(previous) < _minInterval) {
      return Future.value();
    }

    final future = _refresh(scopedAccountUuid, now, force: force);
    _inFlight[scopedAccountUuid] = future;
    return future.whenComplete(() {
      _inFlight.remove(scopedAccountUuid);
    });
  }

  Future<void> _refresh(
    String accountUuid,
    DateTime startedAt, {
    required bool force,
  }) async {
    _lastRefreshAt[accountUuid] = startedAt;
    try {
      final currentIntents = await _tracker.loadIntents(
        accountUuid: accountUuid,
      );
      final dueIds = [
        for (final intent in currentIntents)
          if (_isRefreshDue(intent, accountUuid, startedAt, force: force))
            intent.id,
      ];
      if (dueIds.isEmpty) return;
      await _tracker.refreshIntents(
        accountUuid: accountUuid,
        currentIntents: currentIntents,
        intentIds: dueIds,
        includeTerminal: false,
      );
    } catch (_) {
      // Activity rows are secondary to the wallet shell. Refresh failures are
      // persisted per intent when the provider returns a status error; storage
      // or transport failures should not break Home or Activity rendering.
    }
  }

  bool _isRefreshDue(
    SwapIntent intent,
    String accountUuid,
    DateTime now, {
    required bool force,
  }) {
    if (!SwapActivityTracker._shouldAutoRefreshIntent(
      intent,
      accountUuid: accountUuid,
    )) {
      return false;
    }
    if (force) return true;
    final checkedAt = intent.lastStatusCheckedAt;
    if (checkedAt == null) return true;
    return now.difference(checkedAt.toUtc()) >= _minInterval;
  }
}

class SwapActivityTracker {
  SwapActivityTracker({
    required SwapActivityStore activityStore,
    required SwapProvider swapProvider,
    bool Function()? isTorEnabled,
    void Function()? onRecordsChanged,
    LedgerOperationLifecycle? lifecycle,
    Future<bool?> Function(SwapIntent, SwapIntentSnapshot, DateTime)?
    onProviderSnapshot,
  }) : _activityStore = activityStore is DeletionSafeSwapActivityStore
           ? activityStore
           : DeletionSafeSwapActivityStore(activityStore),
       _swapProvider = swapProvider,
       _isTorEnabled = isTorEnabled,
       _onRecordsChanged = onRecordsChanged,
       _lifecycle = lifecycle,
       _onProviderSnapshot = onProviderSnapshot;

  /// Records a status in the wallet and returns whether the wallet still tracked
  /// the swap's private address, or null when that is unknown.
  final Future<bool?> Function(SwapIntent, SwapIntentSnapshot, DateTime)?
  _onProviderSnapshot;

  /// The wallet deletion drain, which a private swap's status refresh joins
  /// from its request through its saved activity (see [refreshIntents]).
  final LedgerOperationLifecycle? _lifecycle;

  /// The deletion-safe store every read and write goes through.
  final DeletionSafeSwapActivityStore _activityStore;
  final SwapProvider _swapProvider;

  /// Read per refresh, not captured once: Tor can be toggled while an intent is
  /// still open, and the exit-block classification only applies while it is on.
  final bool Function()? _isTorEnabled;
  final void Function()? _onRecordsChanged;

  static String? normalizeAccountUuid(String? accountUuid) {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) return null;
    return scopedAccountUuid;
  }

  /// When this tracker, which lives as long as the app, was created. A swap
  /// still starting that was created earlier lost its start to an app exit, or
  /// its flip to a failed save.
  final DateTime _launchedAt = DateTime.now().toUtc();

  /// `accountUuid`'s saved swaps, with starts finished in this launch cleared
  /// even if saving them failed (see [_finishedStarts]). A private swap left
  /// starting by an earlier launch is marked failed first, keeping it starting
  /// so its instructions stay hidden: its reservation may never have been
  /// locked, and without the request it was quoted with the start cannot be
  /// retried. The wallet still releases or recovers the address on its own.
  Future<List<SwapIntent>> loadIntents({required String? accountUuid}) async {
    final scopedAccountUuid = normalizeAccountUuid(accountUuid);
    if (scopedAccountUuid == null) return const [];
    final records = await _activityStore.loadRecords(
      accountUuid: scopedAccountUuid,
    );
    final intents = withFinishedStarts(
      scopedAccountUuid,
      _intentsFromRecords(records),
    );
    if (!intents.any(_leftStarting)) return intents;
    await updateIntents(
      accountUuid: scopedAccountUuid,
      transform: (saved) => [
        for (final intent in saved)
          _leftStarting(intent) ? _startFailed(intent) : intent,
      ],
    );
    return [
      for (final intent in intents)
        _leftStarting(intent) ? _startFailed(intent) : intent,
    ];
  }

  /// Whether `intent` is still starting from an earlier launch.
  bool _leftStarting(SwapIntent intent) =>
      intent.startPending &&
      !intent.status.isTerminal &&
      !(intent.createdAt?.isAfter(_launchedAt) ?? false);

  /// `intent`, a swap that never finished starting, marked failed.
  static SwapIntent _startFailed(SwapIntent intent) => intent.copyWith(
    status: SwapIntentStatus.failed,
    statusError: swapStartFailedText,
  );

  /// Swaps whose start finished in this launch, by account and id. A start
  /// never goes back to pending, so every load and save clears the flag on
  /// any copy of these, including one read while the swap was still starting.
  final _finishedStarts = <(String, String)>{};

  /// Records that `intentId` on `accountUuid` started once the wallet locked
  /// its reservation, then saves its account's swaps with nothing else
  /// changed, which clears its pending start (see [_finishedStarts]). If that
  /// save fails, loads still read it started, so polling picks it up, and the
  /// account's next save stores it.
  Future<void> finishStart({
    required String accountUuid,
    required String intentId,
  }) {
    final scopedAccountUuid = normalizeAccountUuid(accountUuid);
    if (scopedAccountUuid != null) {
      _finishedStarts.add((scopedAccountUuid, intentId));
    }
    return updateIntents(
      accountUuid: scopedAccountUuid,
      transform: (saved) => saved,
    );
  }

  /// `intents` of `accountUuid` with the pending start cleared on each whose
  /// start finished in this launch (see [_finishedStarts]). Returns `intents`
  /// itself when none needs it.
  List<SwapIntent> withFinishedStarts(
    String accountUuid,
    List<SwapIntent> intents,
  ) {
    bool finished(SwapIntent intent) =>
        intent.startPending &&
        _finishedStarts.contains((accountUuid, intent.id));
    if (!intents.any(finished)) return intents;
    return [
      for (final intent in intents)
        finished(intent) ? intent.copyWith(startPending: false) : intent,
    ];
  }

  /// Hands a provider status, fetched at `checkedAt`, to the wallet when the
  /// swap uses a private address. Ordinary swaps never touch the wallet. A
  /// failure is logged, and the next poll records the status again. A terminal
  /// status ends polling, so its failure fails the refresh instead, which keeps
  /// the swap open until the wallet has it. Returns whether the wallet still
  /// tracked the swap's private address, or null when that is unknown.
  Future<bool?> recordProviderSnapshot(
    SwapIntent intent,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async {
    if (!intent.privateAddress) return null;
    try {
      return await _onProviderSnapshot?.call(intent, snapshot, checkedAt);
    } catch (error) {
      if (snapshot.status.isTerminal) rethrow;
      log('Swap status not recorded in the wallet: $error');
      return null;
    }
  }

  /// Replaces `accountUuid`'s saved swaps with `intents`, through the
  /// deletion-safe store queue, without reading what it replaces. Merges use
  /// [updateIntents] instead.
  Future<void> saveIntents({
    required String? accountUuid,
    required List<SwapIntent> intents,
  }) async {
    final scopedAccountUuid = normalizeAccountUuid(accountUuid);
    if (scopedAccountUuid == null) return;
    await _activityStore.saveRecords(
      accountUuid: scopedAccountUuid,
      records: _persistableRecords(intents, scopedAccountUuid),
    );
    _onRecordsChanged?.call();
  }

  /// Replaces `accountUuid`'s saved swaps with what `transform` makes of them,
  /// as one atomic step of the store (see
  /// [DeletionSafeSwapActivityStore.update]), so a concurrent writer's swaps
  /// are never overwritten by an older list. Every merge goes through here.
  Future<void> updateIntents({
    required String? accountUuid,
    required List<SwapIntent> Function(List<SwapIntent> saved) transform,
  }) async {
    final scopedAccountUuid = normalizeAccountUuid(accountUuid);
    if (scopedAccountUuid == null) return;
    await _activityStore.update(
      accountUuid: scopedAccountUuid,
      transform: (records) => _persistableRecords(
        transform(_intentsFromRecords(records)),
        scopedAccountUuid,
      ),
    );
    _onRecordsChanged?.call();
  }

  /// The records `accountUuid` saves for `intents`, leaving out any it keeps
  /// no record of and clearing finished starts.
  List<SwapIntentRecord> _persistableRecords(
    List<SwapIntent> intents,
    String accountUuid,
  ) => [
    for (final intent in withFinishedStarts(accountUuid, intents))
      if (_isPersistableIntent(intent, accountUuid: accountUuid))
        swapIntentRecordForPersistence(intent, accountUuid: accountUuid),
  ];

  Future<SwapActivityRefreshResult> refreshOpenIntents({
    required String accountUuid,
    required List<SwapIntent> currentIntents,
  }) async {
    final persistedIntents = await loadIntents(accountUuid: accountUuid);
    final sourceIntents = persistedIntents.isEmpty
        ? currentIntents
        : persistedIntents;
    final refreshableIds = [
      for (final intent in sourceIntents)
        if (_shouldAutoRefreshIntent(intent, accountUuid: accountUuid))
          intent.id,
    ];
    return refreshIntents(
      accountUuid: accountUuid,
      currentIntents: sourceIntents,
      intentIds: refreshableIds,
      includeTerminal: false,
    );
  }

  Future<SwapActivityRefreshResult> refreshIntent({
    required String accountUuid,
    required List<SwapIntent> currentIntents,
    required String intentId,
    bool includeTerminal = true,
  }) {
    return refreshIntents(
      accountUuid: accountUuid,
      currentIntents: currentIntents,
      intentIds: [intentId],
      includeTerminal: includeTerminal,
    );
  }

  Future<SwapActivityRefreshResult> refreshIntents({
    required String accountUuid,
    required List<SwapIntent> currentIntents,
    required Iterable<String> intentIds,
    required bool includeTerminal,
  }) async {
    final ids = intentIds.toSet();
    if (ids.isEmpty) {
      return SwapActivityRefreshResult(
        intents: currentIntents,
        requestedIds: ids,
      );
    }
    bool isPrivate(String id) =>
        currentIntents.swapIntentById(id)?.privateAddress ?? false;
    // Ordinary swaps never write the wallet, so they refresh and save outside
    // the wallet deletion drain, as they always have.
    var batch = await _refreshBatch(
      accountUuid: accountUuid,
      currentIntents: currentIntents,
      ids: {
        for (final id in ids)
          if (!isPrivate(id)) id,
      },
      includeTerminal: includeTerminal,
    );
    final privateIds = {
      for (final id in ids)
        if (isPrivate(id)) id,
    };
    final lifecycle = _lifecycle;
    if (privateIds.isNotEmpty && !(lifecycle?.isPaused ?? false)) {
      // Wallet deletion waits for private swaps from their status requests
      // through their wallet writes and saved activity, and none starts while
      // deletion runs, so a late save cannot restore a deleted account's swaps.
      final ordinary = batch;
      Future<_RefreshBatch> refreshPrivate() => _refreshBatch(
        accountUuid: accountUuid,
        currentIntents: ordinary.intents,
        ids: privateIds,
        includeTerminal: includeTerminal,
      );
      final private =
          await (lifecycle?.run(refreshPrivate) ?? refreshPrivate());
      batch = (
        intents: private.intents,
        refreshError: ordinary.refreshError ?? private.refreshError,
        didRefresh: ordinary.didRefresh || private.didRefresh,
      );
    }
    return SwapActivityRefreshResult(
      intents: batch.intents,
      requestedIds: ids,
      refreshError: batch.refreshError,
      didRefresh: batch.didRefresh,
    );
  }

  /// Refreshes the provider statuses of the intents in `ids`, then saves the
  /// refreshed ones. A failed request is recorded on its intent.
  Future<_RefreshBatch> _refreshBatch({
    required String accountUuid,
    required List<SwapIntent> currentIntents,
    required Set<String> ids,
    required bool includeTerminal,
  }) async {
    var updatedIntents = currentIntents;
    var didRefresh = false;
    final refreshedIds = <String>{};
    String? refreshError;

    for (final intent in currentIntents) {
      if (!ids.contains(intent.id)) continue;
      if (!_canRefreshIntent(
        intent,
        accountUuid: accountUuid,
        includeTerminal: includeTerminal,
      )) {
        continue;
      }
      final checkedAt = DateTime.now().toUtc();
      try {
        final updated = await _refreshProviderBackedIntent(
          intent,
          checkedAt: checkedAt,
        );
        updatedIntents = updatedIntents.replaceSwapIntent(intent.id, updated);
      } catch (e) {
        // The raw error is the only way to tell a 1Click outage from a local
        // bug once the policy collapses it into a generic message.
        log('Swap: refresh status failed intent=${intent.id} error=$e');
        final message = swapFailureMessage(
          SwapFailureOperation.refreshStatus,
          e,
          torEnabled: _isTorEnabled?.call() ?? false,
        );
        refreshError ??= message;
        updatedIntents = updatedIntents.replaceSwapIntent(
          intent.id,
          intent.copyWith(lastStatusCheckedAt: checkedAt, statusError: message),
        );
      }
      refreshedIds.add(intent.id);
      didRefresh = true;
    }

    if (didRefresh &&
        updatedIntents.any(
          (intent) => _isPersistableIntent(intent, accountUuid: accountUuid),
        )) {
      await _saveRefreshedIntents(
        accountUuid: accountUuid,
        refreshedIntents: updatedIntents,
        refreshedIds: refreshedIds,
      );
    }
    return (
      intents: updatedIntents,
      refreshError: refreshError,
      didRefresh: didRefresh,
    );
  }

  Future<void> _saveRefreshedIntents({
    required String accountUuid,
    required List<SwapIntent> refreshedIntents,
    required Set<String> refreshedIds,
  }) async {
    await updateIntents(
      accountUuid: accountUuid,
      transform: (latestIntents) {
        var mergedIntents = latestIntents;
        for (final id in refreshedIds) {
          final refreshed = refreshedIntents.swapIntentById(id);
          if (refreshed == null) continue;
          mergedIntents = mergedIntents.replaceSwapIntent(id, refreshed);
        }
        return mergedIntents;
      },
    );
  }

  Future<SwapIntent> _refreshProviderBackedIntent(
    SwapIntent intent, {
    DateTime? checkedAt,
  }) async {
    SwapIntentSnapshot snapshot;
    try {
      snapshot = await _swapProvider.getStatus(
        _providerDepositAddress(intent),
        depositMemo: intent.depositMemo,
      );
    } on OneClickStatusOnlyException catch (error) {
      // The wallet needs a private swap's status even when its amounts cannot
      // be read. An ordinary swap fails the refresh as it always has.
      if (!intent.privateAddress) rethrow;
      snapshot = error.snapshot;
    }
    final tracked = await recordProviderSnapshot(
      intent,
      snapshot,
      checkedAt ?? DateTime.now().toUtc(),
    );
    return updateSwapIntentFromSnapshot(
      intent,
      snapshot,
      updatedAt: checkedAt,
      lastStatusCheckedAt: checkedAt,
    ).copyWith(
      clearStatusError: true,
      walletReleased: intent.walletReleased || tracked == false,
    );
  }

  static String _providerDepositAddress(SwapIntent intent) {
    return intent.depositAddress ?? intent.id;
  }

  static bool _shouldAutoRefreshIntent(
    SwapIntent intent, {
    required String accountUuid,
  }) {
    // An issued external deposit address needs automatic discovery even before
    // the user claims a deposit. Outgoing ZEC needs tracking once a deposit
    // transaction exists, because sync resubmits one whose first broadcast
    // failed, or after the provider has observed a deposit. An unknown
    // provider status does not establish that funds were never sent.
    return _isPersistableIntent(intent, accountUuid: accountUuid) &&
        !intent.startPending &&
        (_awaitsWalletRelease(intent) ||
            (!intent.status.isTerminal &&
                (intent.direction == SwapDirection.externalToZec ||
                    intent.status == SwapIntentStatus.providerStatusUnknown ||
                    intent.depositClaimedAt != null ||
                    (intent.depositTxHash?.trim().isNotEmpty ?? false) ||
                    intent.hasConfirmedDepositEvidence ||
                    intent.hasProviderObservedDepositEvidence)));
  }

  /// Whether an incoming private quote shows as expired while the wallet may
  /// still hold its receive slot. The wallet frees that slot only on a status
  /// fetched after the deadline, which a failed record or a closed app can
  /// miss, so such a quote stays polled until the wallet reports the address
  /// released.
  static bool _awaitsWalletRelease(SwapIntent intent) =>
      intent.status == SwapIntentStatus.expired &&
      intent.direction == SwapDirection.externalToZec &&
      intent.privateAddress &&
      !intent.walletReleased;

  static bool _canRefreshIntent(
    SwapIntent intent, {
    required String accountUuid,
    required bool includeTerminal,
  }) {
    // Its wallet start may still be refused, so it has no status to track.
    if (intent.startPending) return false;
    if (includeTerminal) return intent.status != SwapIntentStatus.complete;
    return _shouldAutoRefreshIntent(intent, accountUuid: accountUuid);
  }

  static bool _isPersistableIntent(
    SwapIntent intent, {
    required String accountUuid,
  }) {
    return intent.accountUuid == accountUuid &&
        intent.direction != null &&
        intent.depositAddress != null &&
        (intent.providerQuoteId != null || intent.depositTxHash != null);
  }
}

List<SwapIntent> _intentsFromRecords(List<SwapIntentRecord> records) {
  return swapIntentsFromRecords(records);
}

/// What one refresh pass changed (see `SwapActivityTracker._refreshBatch`).
typedef _RefreshBatch = ({
  List<SwapIntent> intents,
  String? refreshError,
  bool didRefresh,
});
