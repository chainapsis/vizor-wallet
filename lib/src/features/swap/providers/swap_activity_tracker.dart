import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../models/swap_intent_presentation_mapper.dart';
import '../models/swap_models.dart';
import 'swap_activity_store.dart';
import 'swap_failure_policy.dart';
import 'swap_provider_config.dart';

const swapActivityStatusRefreshInterval = Duration(seconds: 30);

final swapActivityTrackerProvider = Provider<SwapActivityTracker>((ref) {
  return SwapActivityTracker(
    activityStore: ref.read(swapActivityStoreProvider),
    swapProvider: ref.read(swapIntentProvider),
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
  const SwapActivityTracker({
    required SwapActivityStore activityStore,
    required SwapProvider swapProvider,
    void Function()? onRecordsChanged,
  }) : _activityStore = activityStore,
       _swapProvider = swapProvider,
       _onRecordsChanged = onRecordsChanged;

  final SwapActivityStore _activityStore;
  final SwapProvider _swapProvider;
  final void Function()? _onRecordsChanged;

  static String? normalizeAccountUuid(String? accountUuid) {
    final scopedAccountUuid = accountUuid?.trim();
    if (scopedAccountUuid == null || scopedAccountUuid.isEmpty) return null;
    return scopedAccountUuid;
  }

  Future<List<SwapIntent>> loadIntents({required String? accountUuid}) async {
    final scopedAccountUuid = normalizeAccountUuid(accountUuid);
    if (scopedAccountUuid == null) return const [];
    final records = await _activityStore.loadRecords(
      accountUuid: scopedAccountUuid,
    );
    return _intentsFromRecords(records);
  }

  Future<void> saveIntents({
    required String? accountUuid,
    required List<SwapIntent> intents,
  }) async {
    final scopedAccountUuid = normalizeAccountUuid(accountUuid);
    if (scopedAccountUuid == null) return;
    await _activityStore.saveRecords(
      accountUuid: scopedAccountUuid,
      records: [
        for (final intent in intents)
          if (_isPersistableIntent(intent, accountUuid: scopedAccountUuid))
            swapIntentRecordForPersistence(
              intent,
              accountUuid: scopedAccountUuid,
            ),
      ],
    );
    _onRecordsChanged?.call();
  }

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
    return SwapActivityRefreshResult(
      intents: updatedIntents,
      requestedIds: ids,
      refreshError: refreshError,
      didRefresh: didRefresh,
    );
  }

  Future<void> _saveRefreshedIntents({
    required String accountUuid,
    required List<SwapIntent> refreshedIntents,
    required Set<String> refreshedIds,
  }) async {
    final latestIntents = await loadIntents(accountUuid: accountUuid);
    var mergedIntents = latestIntents;
    for (final id in refreshedIds) {
      final refreshed = refreshedIntents.swapIntentById(id);
      if (refreshed == null) continue;
      mergedIntents = mergedIntents.replaceSwapIntent(id, refreshed);
    }
    await saveIntents(accountUuid: accountUuid, intents: mergedIntents);
  }

  Future<SwapIntent> _refreshProviderBackedIntent(
    SwapIntent intent, {
    DateTime? checkedAt,
  }) async {
    final snapshot = await _swapProvider.getStatus(
      _providerDepositAddress(intent),
      depositMemo: intent.depositMemo,
    );
    return updateSwapIntentFromSnapshot(
      intent,
      snapshot,
      updatedAt: checkedAt,
      lastStatusCheckedAt: checkedAt,
    ).copyWith(clearStatusError: true);
  }

  static String _providerDepositAddress(SwapIntent intent) {
    return intent.depositAddress ?? intent.id;
  }

  static bool _shouldAutoRefreshIntent(
    SwapIntent intent, {
    required String accountUuid,
  }) {
    return _isPersistableIntent(intent, accountUuid: accountUuid) &&
        !intent.status.isTerminal;
  }

  static bool _canRefreshIntent(
    SwapIntent intent, {
    required String accountUuid,
    required bool includeTerminal,
  }) {
    if (includeTerminal) return intent.status != SwapIntentStatus.complete;
    if (!_isPersistableIntent(intent, accountUuid: accountUuid)) return false;
    return !intent.status.isTerminal;
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
